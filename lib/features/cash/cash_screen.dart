// Hecho por Briann$ Workers Corp.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/env.dart';
import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import 'cash_report.dart';

/// Cierre de caja de un día, presentado como el ticket Z que imprime una
/// registradora: totales, desglose por método (en su moneda) y anulaciones.
/// Se exporta a PDF, se imprime o se comparte por WhatsApp.
class CashScreen extends ConsumerStatefulWidget {
  const CashScreen({super.key});

  @override
  ConsumerState<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends ConsumerState<CashScreen> {
  DateTime? _day; // null = hoy

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final day = _day ?? today;
    final data = ref.watch(cashDayProvider(day));
    // Sin cash.all cada quien ve solo lo que cobró y vendió él mismo.
    final me = ref.watch(currentStaffProvider).value;
    final onlyMine = !(me?.can(Perm.cashAll) ?? false);

    void go(DateTime d) => setState(() => _day = d.isAfter(today) ? today : d);

    return PageBody(
      header: PageHeader(
        title: 'Caja',
        subtitle: '${day == today ? 'Hoy · ${formatLongDate(day)}' : formatLongDate(day)}${onlyMine ? ' · tus cobros' : ''}',
        actions: [
          IconButton.outlined(
            tooltip: 'Día anterior',
            onPressed: () => go(DateTime(day.year, day.month, day.day - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: today);
              if (picked != null) go(picked);
            },
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(formatDate(day)),
          ),
          IconButton.outlined(
            tooltip: 'Día siguiente',
            onPressed: day == today ? null : () => go(DateTime(day.year, day.month, day.day + 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      children: [
        AsyncView(
          data,
          onRetry: () => ref.invalidate(cashDayProvider(day)),
          data: (d) => _CashDay(
            day: day,
            printedAt: now,
            payments: onlyMine ? d.$1.where((p) => p.createdBy == me?.userId).toList() : d.$1,
            sales: onlyMine ? d.$2.where((s) => s.createdBy == me?.userId).toList() : d.$2,
          ),
        ),
      ],
    );
  }
}

class _CashDay extends StatelessWidget {
  const _CashDay({required this.day, required this.printedAt, required this.payments, required this.sales});

  final DateTime day;
  final DateTime printedAt;
  final List<Payment> payments;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final summary = CashSummary.of(payments, sales);
    final movements = [for (final p in payments) CashMovement.payment(p), for (final s in sales) CashMovement.sale(s)]
      ..sort((a, b) => b.at.compareTo(a.at));

    Future<Uint8List> pdf() async => Uint8List.fromList(await buildCashPdf(
          gymName: Env.gymName,
          day: day,
          printedAt: printedAt,
          summary: summary,
          movements: movements,
        ));
    final fileName = 'cierre-caja-${isoDate(day)}.pdf';

    final ticket = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ZTicket(day: day, printedAt: printedAt, summary: summary, count: movements.where((m) => !m.voided).length),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: () async => Printing.sharePdf(bytes: await pdf(), filename: fileName),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
            OutlinedButton.icon(
              onPressed: () => Printing.layoutPdf(name: fileName, format: PdfPageFormat.roll80, onLayout: (_) => pdf()),
              icon: const Icon(Icons.print_outlined, size: 18),
              label: const Text('Imprimir'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1F8A4C), foregroundColor: Colors.white),
              onPressed: () => launchUrl(
                Uri.https('wa.me', '/', {'text': cashSummaryText(gymName: Env.gymName, day: day, summary: summary)}),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.chat_outlined, size: 18),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
      ],
    );
    final list = Panel(
      title: 'Movimientos · ${movements.length}',
      padding: EdgeInsets.zero,
      child: movements.isEmpty
          ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sin movimientos este día')
          : Column(children: [for (final m in movements) _MovementRow(m: m)]),
    );

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 860) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 28, children: [ticket, list]);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 32,
        children: [SizedBox(width: 400, child: ticket), Expanded(child: list)],
      );
    });
  }
}

class _ZTicket extends StatelessWidget {
  const _ZTicket({required this.day, required this.printedAt, required this.summary, required this.count});

  final DateTime day;
  final DateTime printedAt;
  final CashSummary summary;
  final int count;

  @override
  Widget build(BuildContext context) {
    return PhysicalShape(
      clipper: const _TornEdge(),
      color: AppColors.surface,
      elevation: 0,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.ink, width: 4))),
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 34),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(Env.gymName.toUpperCase(), textAlign: TextAlign.center, style: AppText.score(28)),
            Text('CIERRE DE CAJA · Z', textAlign: TextAlign.center, style: AppText.label.copyWith(color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              '${formatDate(day).toUpperCase()}  ·  IMPRESO ${formatTime(printedAt)}',
              textAlign: TextAlign.center,
              style: AppText.mono(size: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            const Perforation(),
            const SizedBox(height: 12),
            LeaderLine('Membresías', formatMoney(summary.membershipCents)),
            LeaderLine('Tienda', formatMoney(summary.storeCents)),
            const SizedBox(height: 12),
            const Perforation(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink, fontSize: 13)),
                const Spacer(),
                Flexible(
                  child: FittedBox(fit: BoxFit.scaleDown, child: Text(formatMoney(summary.totalCents), style: AppText.score(56))),
                ),
              ],
            ),
            Text('$count ${count == 1 ? 'MOVIMIENTO' : 'MOVIMIENTOS'}', textAlign: TextAlign.right, style: AppText.mono(size: 11, color: AppColors.textMuted)),
            if (summary.totalVesCents > 0) ...[
              const SizedBox(height: 6),
              LeaderLine('Recibido en Bs.', formatVes(summary.totalVesCents), strong: true, color: AppColors.plateBlue),
            ],
            const SizedBox(height: 16),
            Text('POR MÉTODO', style: AppText.label),
            const SizedBox(height: 6),
            if (summary.byMethod.isEmpty) LeaderLine('Sin cobros', '—', color: AppColors.textMuted),
            for (final t in summary.byMethod.values) ...[
              LeaderLine(t.name, t.currency == Currency.ves ? formatVes(t.vesCents) : formatMoney(t.usdCents)),
              if (t.currency == Currency.ves)
                Text('equivale a ${formatMoney(t.usdCents)}', textAlign: TextAlign.right, style: AppText.mono(size: 10.5, color: AppColors.textMuted)),
            ],
            const SizedBox(height: 14),
            const Perforation(),
            const SizedBox(height: 10),
            LeaderLine(
              'Anulaciones (${summary.voidedCount})',
              summary.voidedCount == 0 ? '—' : formatMoney(summary.voidedCents),
              color: summary.voidedCount == 0 ? AppColors.textMuted : AppColors.danger,
            ),
            if (summary.voidedCount > 0)
              Text('No suman al total', textAlign: TextAlign.right, style: AppText.mono(size: 11, color: AppColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// Borde inferior en zigzag: papel arrancado de la registradora.
class _TornEdge extends CustomClipper<Path> {
  const _TornEdge();

  @override
  Path getClip(Size size) {
    const tooth = 10.0;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height - tooth);
    var x = size.width;
    var down = true;
    while (x > 0) {
      x -= tooth;
      path.lineTo(x.clamp(0, size.width), down ? size.height : size.height - tooth);
      down = !down;
    }
    return path..close();
  }

  @override
  bool shouldReclip(_TornEdge old) => false;
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.m});

  final CashMovement m;

  @override
  Widget build(BuildContext context) {
    final strike = m.voided ? TextDecoration.lineThrough : null;
    return Opacity(
      opacity: m.voided ? .5 : 1,
      child: InkWell(
        onTap: () => showDialog<void>(context: context, builder: (_) => _MovementDetail(m: m)),
        hoverColor: AppColors.raised,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          decoration: const BoxDecoration(border: rowRule),
          child: Row(
            children: [
              SizedBox(width: 50, child: Text(formatTime(m.at), style: AppText.mono(size: 12.5, color: AppColors.plateBlue))),
              Container(
                width: 22,
                alignment: Alignment.center,
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.symmetric(vertical: 1),
                color: m.isStore ? AppColors.info : AppColors.plateGreen,
                child: Text(m.isStore ? 'T' : 'M', style: AppText.mono(size: 11, weight: FontWeight.w600, color: AppColors.surface)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.detail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, decoration: strike)),
                    Text(
                      m.voided ? 'ANULADO: ${m.voidReason}' : m.methodName,
                      style: AppText.mono(size: 11.5, color: m.voided ? AppColors.danger : AppColors.textMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(m.usdCents), style: AppText.mono(size: 13, weight: FontWeight.w600).copyWith(decoration: strike)),
                  if (m.vesCents != null)
                    Text(formatVes(m.vesCents!), style: AppText.mono(size: 11, color: AppColors.plateBlue).copyWith(decoration: strike)),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// Detalle de un movimiento: qué se cobró, a quién, cómo y con qué tasa.
class _MovementDetail extends StatelessWidget {
  const _MovementDetail({required this.m});

  final CashMovement m;

  @override
  Widget build(BuildContext context) {
    final p = m.payment;
    final s = m.sale;
    final rate = p?.rate ?? s?.rate;
    final rateSource = p?.rateSource ?? s?.rateSource;
    return FormDialog(
      title: m.isStore ? 'Venta de tienda' : 'Pago de membresía',
      subtitle: '${formatLongDate(m.at)} · ${formatTime(m.at)}',
      width: 480,
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (m.voided)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.danger, width: 1.5)),
              child: Text('ANULADO · ${m.voidReason}', style: AppText.mono(size: 12.5, weight: FontWeight.w600, color: AppColors.danger)),
            ),
          if (p != null) ...[
            LeaderLine('Cliente', p.memberName),
            LeaderLine('Plan', p.planName),
            LeaderLine('Periodo', '${formatShortDate(p.periodStart)} – ${formatDate(p.periodEnd)}'),
          ],
          if (s != null) ...[
            if (s.memberName != null) LeaderLine('Cliente', s.memberName!),
            const SizedBox(height: 6),
            Text('PRODUCTOS', style: AppText.label),
            for (final i in s.items) LeaderLine('${i.quantity} × ${i.productName}', formatMoney(i.totalCents)),
          ],
          const SizedBox(height: 10),
          const Perforation(),
          const SizedBox(height: 10),
          LeaderLine('Método', m.methodName),
          if (rate != null) LeaderLine('Tasa ${rateSource?.label ?? ''}'.trim(), 'Bs. ${formatRate(rate)}', color: AppColors.textMuted),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink)),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatMoney(m.usdCents), style: AppText.score(36)),
                  if (m.vesCents != null) Text(formatVes(m.vesCents!), style: AppText.mono(size: 13, weight: FontWeight.w600, color: AppColors.plateBlue)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
