// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../members/member_dialogs.dart';
import '../payments/payment_dialog.dart';
import 'check_in.dart';

/// Mostrador de entrada: se escribe nombre o cédula y Enter registra al primer
/// resultado. A la derecha, la hoja de firmas del día.
class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  Member? _last;

  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _checkIn(Member m) async {
    if (await checkInMember(context, ref, m) && mounted) {
      setState(() => _last = m);
      _search.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider)();
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final attendance = ref.watch(todayAttendanceProvider);
    final query = _search.text.trim();
    final matches = query.isEmpty ? const <Member>[] : members.where((m) => m.matches(query)).take(6).toList();
    final byId = {for (final m in members) m.id: m};

    final desk = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('QUIÉN LLEGA', style: AppText.label),
        TextField(
          controller: _search,
          focusNode: _focus,
          autofocus: !context.isPhone,
          style: AppText.score(context.isPhone ? 32 : 44),
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => matches.isEmpty ? null : _checkIn(matches.first),
          decoration: InputDecoration(
            hintText: 'Nombre o cédula',
            hintStyle: AppText.score(context.isPhone ? 32 : 44, color: AppColors.borderStrong),
            filled: false,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.ink, width: 3)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.ink, width: 3)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.plateBlue, width: 3)),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Borrar',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.backspace_outlined),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.isPhone ? 'Toca "Entrada" en el cliente' : 'Enter registra al primer resultado',
          style: AppText.mono(size: 11.5, color: AppColors.textMuted),
        ),
        const SizedBox(height: 20),
        if (query.isNotEmpty && matches.isEmpty)
          const EmptyState(icon: Icons.person_off_outlined, title: 'No se encontró a nadie'),
        for (final (i, m) in matches.indexed) _MatchRow(member: m, today: today, first: i == 0, onCheckIn: () => _checkIn(m)),
        if (query.isEmpty && _last != null) _Pass(member: _last!, today: today),
        if (query.isEmpty && _last == null)
          const EmptyState(
            icon: Icons.badge_outlined,
            title: 'Listo para registrar',
            message: 'Busca al cliente cuando llegue. Si su membresía no está al día, verás el aviso aquí.',
          ),
      ],
    );

    final sheet = _SignInSheet(attendance: attendance, byId: byId, today: today);

    return PageBody(
      header: PageHeader(title: 'Asistencia', subtitle: formatLongDate(today)),
      children: [
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 900) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 32, children: [desk, sheet]);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 36,
            children: [Expanded(flex: 3, child: desk), Expanded(flex: 2, child: sheet)],
          );
        }),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.member, required this.today, required this.first, required this.onCheckIn});

  final Member member;
  final DateTime today;
  final bool first;
  final VoidCallback onCheckIn;

  @override
  Widget build(BuildContext context) {
    final status = member.status(today);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: first ? AppColors.ink : AppColors.border, width: first ? 1.5 : 1),
      ),
      child: Row(
        children: [
          Initials(member, size: 44, status: status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(member.documentId == null ? 'Sin cédula' : formatDocument(member.documentId), style: AppText.mono(size: 12, color: AppColors.textMuted)),
                    StatusBadge(status),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (first && !context.isPhone) ...[
            Text('ENTER', style: AppText.label),
            const SizedBox(width: 10),
          ],
          FilledButton(onPressed: onCheckIn, child: const Text('Entrada')),
        ],
      ),
    );
  }
}

/// Resultado del último registro como un pase de entrada con talón
/// perforado y el sello grande: legible desde el otro lado del mostrador.
class _Pass extends StatelessWidget {
  const _Pass({required this.member, required this.today});

  final Member member;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final status = member.status(today);
    final ok = status == MembershipStatus.active || status == MembershipStatus.expiringSoon;
    final expires = member.expiresOn;
    final color = AppColors.forStatus(status);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppColors.ink, width: 1.5),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Talón con la hora.
            Container(
              width: 76,
              color: color,
              alignment: Alignment.center,
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(ok ? 'PASE' : 'COBRAR', style: AppText.score(26, color: AppColors.surface)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ok ? 'BIENVENIDO' : (status == MembershipStatus.inactive ? 'CLIENTE INACTIVO · COBRAR LO REACTIVA' : 'MEMBRESÍA NO AL DÍA'),
                      style: AppText.label,
                    ),
                    const SizedBox(height: 4),
                    Text(member.fullName.toUpperCase(), style: AppText.score(context.isPhone ? 30 : 38)),
                    const SizedBox(height: 8),
                    Text(
                      expires == null
                          ? 'No tiene pagos registrados'
                          : '${member.planName ?? 'Plan'} · ${relativeDays(daysLeft(expires, today))} (${formatDate(expires)})',
                      style: AppText.mono(size: 12.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 14,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        StatusBadge(status, large: true),
                        if (!ok || status == MembershipStatus.expiringSoon)
                          FilledButton(onPressed: () => showPaymentDialog(context, member: member), child: const Text('Cobrar ahora')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja de firmas: renglones con margen rojo, hora en tinta azul.
class _SignInSheet extends ConsumerWidget {
  const _SignInSheet({required this.attendance, required this.byId, required this.today});

  final AsyncValue<List<Attendance>> attendance;
  final Map<String, Member> byId;
  final DateTime today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = attendance.value?.length ?? 0;
    return Panel(
      title: 'Hoja de entradas',
      trailing: Text(count.toString().padLeft(2, '0'), style: AppText.score(30, color: AppColors.plateBlue)),
      padding: EdgeInsets.zero,
      child: AsyncView(
        attendance,
        onRetry: () => ref.invalidate(todayAttendanceProvider),
        data: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.door_front_door_outlined, title: 'Sin entradas todavía')
            : Column(
                children: [
                  for (final a in list)
                    InkWell(
                      onTap: byId[a.memberId] == null ? null : () => showMemberDetail(context, byId[a.memberId]!),
                      hoverColor: AppColors.raised,
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.only(right: 14),
                        decoration: const BoxDecoration(border: rowRule),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 64,
                              child: Text(formatTime(a.checkedInAt), textAlign: TextAlign.center, style: AppText.mono(color: AppColors.plateBlue)),
                            ),
                            // Margen rojo del cuaderno.
                            Container(width: 1.5, color: AppColors.plateRed.withValues(alpha: .55)),
                            const SizedBox(width: 14),
                            Expanded(child: Text(a.memberName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5))),
                            if (byId[a.memberId] case final m?) StatusBadge(m.status(today)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
