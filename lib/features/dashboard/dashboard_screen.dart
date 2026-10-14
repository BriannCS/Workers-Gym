// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../members/member_dialogs.dart';
import '../payments/payment_dialog.dart';

/// Parte del día: marcador arriba; a la izquierda a quién llamar para renovar,
/// a la derecha la cinta de ingresos, la nota de stock y la hoja de entradas.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider)();
    final members = ref.watch(membersProvider);
    final payments = ref.watch(paymentsProvider).value ?? const <Payment>[];
    final sales = ref.watch(salesProvider).value ?? const <Sale>[];
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final attendance = ref.watch(todayAttendanceProvider).value ?? const <Attendance>[];

    return PageBody(
      header: PageHeader(
        title: 'Hoy',
        subtitle: '${formatLongDate(today)} · parte del día',
        actions: [
          OutlinedButton.icon(
            onPressed: () => showMemberForm(context),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Nuevo cliente'),
          ),
          FilledButton.icon(
            onPressed: () => showPaymentDialog(context),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Registrar pago'),
          ),
        ],
      ),
      children: [
        AsyncView(
          members,
          onRetry: () => refreshGymData(ref),
          data: (list) => _Content(
            members: list,
            payments: payments,
            sales: sales,
            products: products,
            attendance: attendance,
            today: today,
          ),
        ),
      ],
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.members,
    required this.payments,
    required this.sales,
    required this.products,
    required this.attendance,
    required this.today,
  });

  final List<Member> members;
  final List<Payment> payments;
  final List<Sale> sales;
  final List<Product> products;
  final List<Attendance> attendance;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final byStatus = {for (final s in MembershipStatus.values) s: <Member>[]};
    for (final m in members) {
      byStatus[m.status(today)]!.add(m);
    }
    bool sameMonth(DateTime d, DateTime ref) => d.year == ref.year && d.month == ref.month;
    CashSummary month(DateTime m) => CashSummary.of(
          payments.where((p) => sameMonth(p.paidAt, m)),
          sales.where((s) => sameMonth(s.soldAt, m)),
        );
    final thisMonth = month(today);
    final previous = month(DateTime(today.year, today.month - 1));
    final lowStock = products.where((p) => p.active && p.lowStock).toList()..sort((a, b) => a.stock.compareTo(b.stock));

    // Por vencer primero, luego vencidos recientes (últimos 15 días): a quién llamar hoy.
    final followUp = [
      ...byStatus[MembershipStatus.expiringSoon]!,
      ...byStatus[MembershipStatus.expired]!.where((m) => daysLeft(m.expiresOn!, today) >= -15),
    ]..sort((a, b) => b.expiresOn!.compareTo(a.expiresOn!));

    final active = byStatus[MembershipStatus.active]!.length + byStatus[MembershipStatus.expiringSoon]!.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScoreBoard(scores: [
          Score(
            label: 'Entradas hoy',
            value: '${attendance.length}',
            color: AppColors.plateBlue,
            caption: attendance.isEmpty ? 'Aún no entra nadie' : 'Última a las ${formatTime(attendance.first.checkedInAt)}',
            onTap: () => context.go('/asistencia'),
          ),
          Score(
            label: 'Al día',
            value: '$active',
            color: AppColors.success,
            caption: 'de ${members.length} clientes',
            onTap: () => context.go('/clientes'),
          ),
          Score(
            label: 'Por vencer',
            value: '${byStatus[MembershipStatus.expiringSoon]!.length}',
            color: AppColors.warning,
            caption: 'en $expiringSoonDays días o menos',
            onTap: () => context.go('/clientes'),
          ),
          Score(
            label: 'Vencidos',
            value: '${byStatus[MembershipStatus.expired]!.length}',
            color: AppColors.danger,
            caption: '${byStatus[MembershipStatus.none]!.length} nunca han pagado',
            onTap: () => context.go('/clientes'),
          ),
        ]),
        const SizedBox(height: 28),
        LayoutBuilder(builder: (context, c) {
          final follow = _CallList(members: followUp, today: today);
          final side = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 24,
            children: [
              _RevenueTape(month: thisMonth, previous: previous.totalCents, today: today),
              if (lowStock.isNotEmpty) _LowStockNote(products: lowStock),
              _SignInSheet(attendance: attendance),
            ],
          );
          if (c.maxWidth < 900) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [follow, side]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 28,
            children: [Expanded(flex: 7, child: follow), Expanded(flex: 5, child: side)],
          );
        }),
      ],
    );
  }
}

/// Lista de llamadas: por vencer y vencidos recientes, con su teléfono.
class _CallList extends StatelessWidget {
  const _CallList({required this.members, required this.today});

  final List<Member> members;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Llamar para renovar · ${members.length}',
      padding: EdgeInsets.zero,
      child: members.isEmpty
          ? const EmptyState(icon: Icons.check, title: 'Todo al día', message: 'Nadie vence en los próximos días.')
          : Column(children: [for (final m in members.take(10)) _CallRow(member: m, today: today)]),
    );
  }
}

class _CallRow extends StatelessWidget {
  const _CallRow({required this.member, required this.today});

  final Member member;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final status = member.status(today);
    final left = daysLeft(member.expiresOn!, today);
    final renew = OutlinedButton(
      onPressed: () => showPaymentDialog(context, member: member),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
      child: const Text('Renovar'),
    );
    return InkWell(
      onTap: () => showMemberDetail(context, member),
      hoverColor: AppColors.raised,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(border: rowRule),
        child: LayoutBuilder(builder: (context, c) {
          final when = Text(
            relativeDays(left).toUpperCase(),
            style: AppText.mono(size: 12, weight: FontWeight.w600, color: AppColors.forStatus(status)),
          );
          final who = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('${member.planName ?? '—'} · ${member.phone == null ? 'sin teléfono' : formatPhone(member.phone)}', style: AppText.mono(size: 12, color: AppColors.textMuted)),
            ],
          );
          if (c.maxWidth < 440) {
            return Row(
              children: [
                Initials(member, status: status),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [who, const SizedBox(height: 4), when])),
                renew,
              ],
            );
          }
          return Row(
            children: [
              Initials(member, status: status),
              const SizedBox(width: 14),
              Expanded(child: who),
              SizedBox(width: 120, child: Align(alignment: Alignment.centerRight, child: when)),
              const SizedBox(width: 16),
              renew,
            ],
          );
        }),
      ),
    );
  }
}

/// Ingresos del mes como cinta de caja registradora.
class _RevenueTape extends StatelessWidget {
  const _RevenueTape({required this.month, required this.previous, required this.today});

  final CashSummary month;
  final int previous;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final total = month.totalCents;
    final diff = previous == 0 ? null : (total - previous) / previous * 100;
    final up = (diff ?? 0) >= 0;
    final monthName = DateFormat('MMMM', 'es').format(today).toUpperCase();
    return Material(
      color: AppColors.surface,
      shape: const RoundedRectangleBorder(side: BorderSide(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('INGRESOS · $monthName', style: AppText.label)),
                TextButton(onPressed: () => context.go('/caja'), child: const Text('Caja')),
              ],
            ),
            const Perforation(),
            const SizedBox(height: 12),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatMoney(total), style: AppText.score(60)),
            ),
            if (diff != null)
              Row(
                children: [
                  Icon(up ? Icons.trending_up : Icons.trending_down, size: 16, color: up ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 6),
                  Text(
                    '${up ? '+' : '-'}${diff.abs().toStringAsFixed(0)}% vs. mes anterior',
                    style: AppText.mono(size: 12, weight: FontWeight.w600, color: up ? AppColors.success : AppColors.danger),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            LeaderLine('Membresías', formatMoney(month.membershipCents)),
            LeaderLine('Tienda', formatMoney(month.storeCents)),
            LeaderLine('Mes anterior', formatMoney(previous), color: AppColors.textMuted),
            const SizedBox(height: 10),
            const Perforation(),
          ],
        ),
      ),
    );
  }
}

class _LowStockNote extends StatelessWidget {
  const _LowStockNote({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return StickyNote(
      title: 'Reponer',
      trailing: IconButton(
        tooltip: 'Ir a inventario',
        onPressed: () => context.go('/inventario'),
        icon: const Icon(Icons.arrow_forward, color: AppColors.ink, size: 20),
      ),
      child: Column(
        children: [
          for (final p in products.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                  Text(p.stock == 0 ? 'AGOTADO' : 'QUEDAN ${p.stock}', style: AppText.mono(size: 12, weight: FontWeight.w600)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Últimas entradas como la hoja de firmas del mostrador.
class _SignInSheet extends StatelessWidget {
  const _SignInSheet({required this.attendance});

  final List<Attendance> attendance;

  @override
  Widget build(BuildContext context) {
    return Panel(
      title: 'Hoja de entradas',
      trailing: TextButton(onPressed: () => context.go('/asistencia'), child: const Text('Registrar')),
      padding: EdgeInsets.zero,
      child: attendance.isEmpty
          ? const EmptyState(icon: Icons.door_front_door_outlined, title: 'Sin entradas hoy')
          : Column(
              children: [
                for (final a in attendance.take(6))
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: const BoxDecoration(border: rowRule),
                    child: Row(
                      children: [
                        SizedBox(width: 56, child: Text(formatTime(a.checkedInAt), style: AppText.mono(color: AppColors.plateBlue))),
                        Container(width: 1, height: 18, color: AppColors.plateRed.withValues(alpha: .5)),
                        const SizedBox(width: 14),
                        Expanded(child: Text(a.memberName, overflow: TextOverflow.ellipsis)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
