// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../attendance/check_in.dart';
import '../payments/payment_dialog.dart';
import 'member_actions.dart';
import 'member_dialogs.dart';

/// Planilla de clientes: tabla en pantallas anchas, fichas en angostas.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key});

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  String _query = '';
  MembershipStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider)();
    final members = ref.watch(membersProvider);
    final all = members.value ?? const <Member>[];
    int count(MembershipStatus? s) => s == null ? all.length : all.where((m) => m.status(today) == s).length;

    final filters = [
      for (final s in [null, ...MembershipStatus.values])
        ChoiceChip(
          label: Text('${s?.label ?? 'Todos'}  ${count(s)}'),
          selected: _filter == s,
          onSelected: (_) => setState(() => _filter = s),
          avatar: s == null ? null : Container(width: 8, height: 8, color: AppColors.forStatus(s)),
        ),
    ];

    return PageBody(
      header: PageHeader(
        title: 'Clientes',
        subtitle: '${all.length} en la planilla',
        actions: [
          if (ref.watch(canProvider(Perm.membersEdit)))
            FilledButton.icon(
              onPressed: () => showMemberForm(context),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Nuevo cliente'),
            ),
        ],
      ),
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: const InputDecoration(hintText: 'Buscar por nombre, cédula o teléfono', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        const SizedBox(height: 12),
        if (context.isPhone)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(spacing: 8, children: filters),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: filters),
        const SizedBox(height: 20),
        Panel(
          padding: EdgeInsets.zero,
          child: AsyncView(
            members,
            onRetry: () => refreshGymData(ref),
            data: (list) {
              final visible = list.where((m) => m.matches(_query) && (_filter == null || m.status(today) == _filter)).toList();
              if (visible.isEmpty) {
                return EmptyState(
                  icon: Icons.person_search_outlined,
                  title: list.isEmpty ? 'Planilla vacía' : 'Sin resultados',
                  message: list.isEmpty ? 'Registra al primer cliente para empezar.' : 'Prueba con otro nombre o filtro.',
                  action: list.isEmpty && ref.watch(canProvider(Perm.membersEdit))
                      ? FilledButton(onPressed: () => showMemberForm(context), child: const Text('Nuevo cliente'))
                      : null,
                );
              }
              return LayoutBuilder(builder: (context, c) {
                if (c.maxWidth < 760) {
                  return Column(children: [for (final m in visible) _MemberCard(member: m, today: today)]);
                }
                return Column(
                  children: [
                    const TableHeader(cells: [('Cliente', 5), ('Teléfono', 3), ('Plan', 3), ('Vence', 3), ('Estado', 3), ('', 3)]),
                    for (final m in visible) _MemberRow(member: m, today: today),
                  ],
                );
              });
            },
          ),
        ),
      ],
    );
  }
}

List<Widget> _actions(BuildContext context, WidgetRef ref, Member member) => [
      if (ref.watch(canProvider(Perm.attendanceCreate)))
        IconButton(tooltip: 'Registrar entrada', onPressed: () => checkInMember(context, ref, member), icon: const Icon(Icons.login, size: 20)),
      if (ref.watch(canProvider(Perm.paymentsCreate)))
        IconButton(
          tooltip: 'Registrar pago',
          onPressed: () => showPaymentDialog(context, member: member),
          icon: const Icon(Icons.payments_outlined, size: 20),
        ),
      // Editar, activar/desactivar y eliminar (también al mantener presionado).
      if (ref.watch(canProvider(Perm.membersEdit)) || ref.watch(canProvider(Perm.membersDelete)))
        IconButton(
          tooltip: 'Más opciones',
          onPressed: () => showMemberActions(context, member),
          icon: const Icon(Icons.more_vert, size: 20),
        ),
    ];

class _MemberRow extends ConsumerWidget {
  const _MemberRow({required this.member, required this.today});

  final Member member;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = member.status(today);
    final expires = member.expiresOn;
    return InkWell(
      onTap: () => showMemberDetail(context, member),
      onLongPress: () => showMemberActions(context, member),
      onSecondaryTap: () => showMemberActions(context, member),
      hoverColor: AppColors.raised,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Initials(member, status: status),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5), overflow: TextOverflow.ellipsis),
                        Text(member.documentId == null ? 'Sin cédula' : formatDocument(member.documentId), style: AppText.mono(size: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(flex: 3, child: Text(formatPhone(member.phone), style: AppText.mono(size: 12.5, color: AppColors.textMuted))),
            Expanded(flex: 3, child: Text(member.planName ?? '—', style: const TextStyle(fontSize: 14))),
            Expanded(
              flex: 3,
              child: expires == null
                  ? const Text('—', style: AppText.muted)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatDate(expires), style: AppText.mono(size: 12.5)),
                        Text(relativeDays(daysLeft(expires, today)), style: AppText.muted.copyWith(fontSize: 12)),
                      ],
                    ),
            ),
            Expanded(flex: 3, child: Align(alignment: Alignment.centerLeft, child: StatusBadge(status))),
            Expanded(flex: 3, child: Row(mainAxisAlignment: MainAxisAlignment.end, children: _actions(context, ref, member))),
          ],
        ),
      ),
    );
  }
}

class _MemberCard extends ConsumerWidget {
  const _MemberCard({required this.member, required this.today});

  final Member member;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = member.status(today);
    final expires = member.expiresOn;
    return InkWell(
      onTap: () => showMemberDetail(context, member),
      onLongPress: () => showMemberActions(context, member),
      onSecondaryTap: () => showMemberActions(context, member),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        decoration: const BoxDecoration(border: rowRule),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Initials(member, size: 44, status: status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                      const SizedBox(height: 2),
                      Text(
                        [if (member.documentId != null) formatDocument(member.documentId), if (member.phone != null) formatPhone(member.phone)].join(' · '),
                        style: AppText.mono(size: 12, color: AppColors.textMuted),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                StatusBadge(status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    expires == null
                        ? 'Nunca ha pagado'
                        : '${member.planName ?? 'Plan'} · ${relativeDays(daysLeft(expires, today))}',
                    style: AppText.muted.copyWith(fontSize: 12.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ..._actions(context, ref, member),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
