// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import 'payment_dialog.dart';

/// Libro de pagos de membresías.
class PaymentsScreen extends ConsumerWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider)();
    final payments = ref.watch(paymentsProvider);
    final valid = (payments.value ?? const <Payment>[]).where((p) => !p.voided);

    bool inMonth(Payment p, DateTime m) => p.paidAt.year == m.year && p.paidAt.month == m.month;
    int total(Iterable<Payment> ps) => ps.fold(0, (s, p) => s + p.amountCents);
    final thisMonth = valid.where((p) => inMonth(p, today)).toList();
    final lastMonth = valid.where((p) => inMonth(p, DateTime(today.year, today.month - 1))).toList();
    final todays = valid.where((p) => dateOnly(p.paidAt) == dateOnly(today)).toList();

    return PageBody(
      header: PageHeader(
        title: 'Pagos',
        subtitle: 'Libro de membresías cobradas',
        actions: [
          if (ref.watch(canProvider(Perm.paymentsCreate)))
            FilledButton.icon(
              onPressed: () => showPaymentDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar pago'),
            ),
        ],
      ),
      children: [
        // Los totales son ingresos: solo con permiso (recepción no los ve).
        if (ref.watch(canProvider(Perm.dashboardMoney))) ...[
          ScoreBoard(scores: [
            Score(label: 'Hoy', value: formatMoney(total(todays)), caption: '${todays.length} pagos', color: AppColors.plateBlue),
            Score(label: 'Este mes', value: formatMoney(total(thisMonth)), caption: '${thisMonth.length} pagos', color: AppColors.success),
            Score(label: 'Mes anterior', value: formatMoney(total(lastMonth)), caption: '${lastMonth.length} pagos'),
          ]),
          const SizedBox(height: 28),
        ],
        Panel(
          title: 'Asientos',
          padding: EdgeInsets.zero,
          child: AsyncView(
            payments,
            onRetry: () => ref.invalidate(paymentsProvider),
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sin pagos registrados')
                : LayoutBuilder(
                    builder: (context, c) => Column(
                      children: [
                        if (c.maxWidth >= 760)
                          const TableHeader(
                            cells: [('Fecha', 3), ('Cliente', 5), ('Plan', 3), ('Periodo', 4), ('Método', 3), ('Monto', 2), ('', 1)],
                          ),
                        for (final p in list) _PaymentRow(payment: p, compact: c.maxWidth < 760),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PaymentRow extends ConsumerWidget {
  const _PaymentRow({required this.payment, required this.compact});

  final Payment payment;
  final bool compact;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final reason = await askVoidReason(
      context,
      title: 'Anular pago',
      detail: '${payment.memberName} · ${payment.planName} · ${formatMoney(payment.amountCents)}',
    );
    if (reason == null) return;
    try {
      await ref.read(gymRepositoryProvider).voidPayment(payment.id, reason);
      refreshGymData(ref);
      if (context.mounted) showToast(context, 'Pago anulado');
    } catch (e) {
      if (context.mounted) showToast(context, 'No se pudo anular: ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = payment;
    final strike = p.voided ? TextDecoration.lineThrough : null;
    final muted = AppText.mono(size: 12.5, color: AppColors.textMuted).copyWith(decoration: strike);
    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(formatMoney(p.amountCents), textAlign: TextAlign.right, style: AppText.mono(size: 14, weight: FontWeight.w600).copyWith(decoration: strike)),
        if (p.amountVesCents != null)
          Text(formatVes(p.amountVesCents!), textAlign: TextAlign.right, style: muted.copyWith(fontSize: 11, color: AppColors.plateBlue)),
      ],
    );
    final voidButton = p.voided || !ref.watch(canProvider(Perm.paymentsVoid))
        ? const SizedBox(width: 40)
        : IconButton(tooltip: 'Anular pago', onPressed: () => _void(context, ref), icon: const Icon(Icons.block, size: 18));
    final method = Text(p.voided ? 'ANULADO' : p.methodName, style: muted.copyWith(color: p.voided ? AppColors.danger : null));

    final Widget row;
    if (compact) {
      row = Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.memberName, style: TextStyle(fontWeight: FontWeight.w600, decoration: strike), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${p.planName} · ${formatShortDate(p.periodStart)} – ${formatShortDate(p.periodEnd)}', style: muted, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${formatShortDate(p.paidAt)} ${formatTime(p.paidAt)} · ${p.voided ? 'ANULADO' : p.methodName}',
                    style: muted.copyWith(color: p.voided ? AppColors.danger : null),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            amount,
            voidButton,
          ],
        ),
      );
    } else {
      row = Container(
        padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
        constraints: const BoxConstraints(minHeight: 52),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text('${formatShortDate(p.paidAt)} · ${formatTime(p.paidAt)}', style: muted)),
            Expanded(
              flex: 5,
              child: Text(p.memberName, style: TextStyle(fontWeight: FontWeight.w600, decoration: strike), overflow: TextOverflow.ellipsis),
            ),
            Expanded(flex: 3, child: Text(p.planName, style: const TextStyle(fontSize: 14))),
            Expanded(flex: 4, child: Text('${formatShortDate(p.periodStart)} – ${formatShortDate(p.periodEnd)}', style: muted)),
            Expanded(flex: 3, child: method),
            Expanded(flex: 2, child: amount),
            Expanded(flex: 1, child: Align(alignment: Alignment.centerRight, child: voidButton)),
          ],
        ),
      );
    }
    final faded = Opacity(opacity: p.voided ? .55 : 1, child: row);
    return p.voided ? Tooltip(message: 'Anulado: ${p.voidReason}', child: faded) : faded;
  }
}
