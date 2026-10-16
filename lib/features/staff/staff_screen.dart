// Hecho por Briann$ - Workers Corp.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/staff_controls.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart' show onlyDigits;
import '../../domain/staff.dart';

/// Control de personal: quién trabaja aquí, con qué rol, en qué horario y qué
/// hizo. Los permisos también se comprueban en el servidor.
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

enum _Tab { people, roles, audit }

class _StaffScreenState extends ConsumerState<StaffScreen> {
  _Tab _tab = _Tab.people;

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canProvider(Perm.staffManage));
    final canAudit = ref.watch(canProvider(Perm.auditView));
    return PageBody(
      header: PageHeader(
        title: 'Personal',
        subtitle: 'Equipo, roles, turnos y bitácora',
        actions: [
          if (canManage)
            FilledButton.icon(
              onPressed: () => showStaffForm(context),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Nueva persona'),
            ),
        ],
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<_Tab>(
              segments: [
                const ButtonSegment(value: _Tab.people, label: Text('Equipo'), icon: Icon(Icons.groups_outlined)),
                const ButtonSegment(value: _Tab.roles, label: Text('Roles y permisos'), icon: Icon(Icons.admin_panel_settings_outlined)),
                if (canAudit) const ButtonSegment(value: _Tab.audit, label: Text('Bitácora'), icon: Icon(Icons.history)),
              ],
              selected: {_tab == _Tab.audit && !canAudit ? _Tab.people : _tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
        ),
        const SizedBox(height: 20),
        switch (_tab) {
          _Tab.people => const _People(),
          _Tab.roles => const _RolesMatrix(),
          _Tab.audit => canAudit ? const _AuditLog() : const _People(),
        },
      ],
    );
  }
}

Color roleColor(StaffRole r) => switch (r) {
  StaffRole.owner => AppColors.ink,
  StaffRole.admin => AppColors.plateBlue,
  StaffRole.reception => AppColors.plateGreen,
  StaffRole.trainer => AppColors.warning,
};

class RoleBadge extends StatelessWidget {
  const RoleBadge(this.role, {super.key});

  final StaffRole role;

  @override
  Widget build(BuildContext context) {
    final c = roleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: c, width: 1.2),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Text(
        role.label.toUpperCase(),
        style: AppText.label.copyWith(color: c, fontWeight: FontWeight.w600, fontSize: 10),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.member, {this.size = 40});

  final StaffMember member;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = member.fullName.trim().split(RegExp(r'\s+'));
    final initials = (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
    final c = member.active ? roleColor(member.role) : AppColors.textMuted;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.raised,
            border: Border(bottom: BorderSide(color: c, width: 3)),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Text(initials, style: AppText.score(size * .45, color: AppColors.ink)),
        ),
        if (member.onShift)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Equipo

class _People extends ConsumerWidget {
  const _People();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staff = ref.watch(staffDirectoryProvider);
    final entries = ref.watch(staffTimeEntriesProvider).value ?? const <StaffTimeEntry>[];
    final now = ref.watch(clockProvider)();
    return AsyncView(
      staff,
      onRetry: () => ref.invalidate(staffDirectoryProvider),
      data: (list) {
        final active = list.where((s) => s.active).toList();
        final monthHours = workedInMonth(entries, now, now);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScoreBoard(
              scores: [
                Score(label: 'Activos', value: '${active.length}', caption: 'de ${list.length} en total'),
                Score(
                  label: 'En turno ahora',
                  value: '${active.where((s) => s.onShift).length}',
                  color: AppColors.success,
                  caption: active.where((s) => s.onShift).map((s) => s.fullName.split(' ').first).join(', ').ifEmpty('Nadie marcó entrada'),
                ),
                Score(
                  label: 'Suspendidos',
                  value: '${list.where((s) => s.status == StaffStatus.suspended).length}',
                  color: AppColors.danger,
                  caption: '${list.where((s) => s.status == StaffStatus.terminated).length} de baja',
                ),
                Score(
                  label: 'Horas del mes',
                  value: '${monthHours.inHours}',
                  color: AppColors.plateBlue,
                  caption: 'trabajadas por todo el equipo',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Panel(
              title: 'Equipo · ${list.length}',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final s in list) _StaffRow(member: s, entries: entries.where((e) => e.userId == s.userId).toList(), now: now),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _StaffRow extends StatelessWidget {
  const _StaffRow({required this.member, required this.entries, required this.now});

  final StaffMember member;
  final List<StaffTimeEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final phone = context.isPhone;
    final hours = workedInMonth(entries, now, now);
    final status = switch (member.status) {
      StaffStatus.active => member.onShift ? 'En turno desde ${formatTime(member.onShiftSince!)}' : 'Fuera de turno',
      _ => member.status.label,
    };
    return InkWell(
      onTap: () => showStaffDetail(context, member.userId),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            _Avatar(member),
            const SizedBox(width: 14),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(
                    member.fullName,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: member.active ? AppColors.text : AppColors.textMuted,
                      decoration: member.status == StaffStatus.terminated ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      RoleBadge(member.role),
                      Text(
                        status,
                        style: AppText.mono(
                          size: 11.5,
                          color: member.status == StaffStatus.suspended
                              ? AppColors.danger
                              : member.onShift
                              ? AppColors.success
                              : AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!phone) ...[
              Expanded(
                flex: 3,
                child: Text(formatPhone(member.phone).ifEmpty('—'), style: AppText.mono(size: 12.5, color: AppColors.textMuted)),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  member.lastSignInAt == null ? 'Sin ingresos' : 'Último ingreso ${formatShortDate(member.lastSignInAt!)}',
                  style: AppText.mono(size: 12, color: AppColors.textMuted),
                ),
              ),
            ],
            SizedBox(
              width: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${hours.inHours} h', style: AppText.score(22)),
                  Text('ESTE MES', style: AppText.label.copyWith(fontSize: 9)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ficha del empleado

Future<void> showStaffDetail(BuildContext context, String userId) => showDialog<void>(
  context: context,
  builder: (_) => _StaffDetail(userId: userId),
);

class _StaffDetail extends ConsumerStatefulWidget {
  const _StaffDetail({required this.userId});

  final String userId;

  @override
  ConsumerState<_StaffDetail> createState() => _StaffDetailState();
}

class _StaffDetailState extends ConsumerState<_StaffDetail> {
  bool _busy = false;

  Future<void> _setStatus(StaffMember m, StaffStatus status) async {
    final verb = switch (status) {
      StaffStatus.active => 'Reactivar',
      StaffStatus.suspended => 'Suspender',
      StaffStatus.terminated => 'Dar de baja',
    };
    final detail = switch (status) {
      StaffStatus.active => '${m.fullName} podrá volver a entrar a la app con su rol de ${m.role.label}.',
      StaffStatus.suspended => '${m.fullName} pierde el acceso al instante. Su historial se conserva y puedes reactivarlo cuando quieras.',
      StaffStatus.terminated =>
        '${m.fullName} deja el gimnasio: pierde el acceso y queda en el historial. Sus cobros y ventas no se borran.',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$verb a ${m.fullName.split(' ').first}'),
        content: Text(detail),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: status == StaffStatus.active ? null : FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: Text(verb),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).setStaffStatus(m.userId, status);
      ref
        ..invalidate(staffDirectoryProvider)
        ..invalidate(staffTimeEntriesProvider)
        ..invalidate(auditLogProvider);
      if (mounted) showToast(context, '${m.fullName}: ${status.label.toLowerCase()}');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(staffDirectoryProvider).value ?? const <StaffMember>[];
    final m = list.where((s) => s.userId == widget.userId).firstOrNull;
    if (m == null) return const SizedBox.shrink();
    final me = ref.watch(currentStaffProvider).value;
    final isOwnerTarget = m.role == StaffRole.owner;
    final canManage = (me?.can(Perm.staffManage) ?? false) && (!isOwnerTarget || me?.role == StaffRole.owner);
    final isMe = me?.userId == m.userId;
    final shifts = ref.watch(staffShiftsProvider(m.userId)).value ?? const <StaffShift>[];
    final entries = (ref.watch(staffTimeEntriesProvider).value ?? const <StaffTimeEntry>[]).where((e) => e.userId == m.userId).toList();
    final now = ref.watch(clockProvider)();
    final lateCount = entries.where((e) => e.clockIn.month == now.month && e.clockIn.year == now.year && lateMinutes(e, shifts) > 0).length;

    return FormDialog(
      title: m.fullName,
      subtitle: '${m.role.label} · ${m.status.label}',
      width: 640,
      headerActions: [
        if (canManage)
          IconButton(
            tooltip: 'Editar datos y rol',
            onPressed: () => showStaffForm(context, member: m),
            icon: const Icon(Icons.edit_outlined),
          ),
      ],
      actions: [
        if (canManage && !isMe) ...[
          if (m.status == StaffStatus.active) ...[
            OutlinedButton(onPressed: _busy ? null : () => _setStatus(m, StaffStatus.terminated), child: const Text('Dar de baja')),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
              onPressed: _busy ? null : () => _setStatus(m, StaffStatus.suspended),
              child: const Text('Suspender'),
            ),
          ] else
            FilledButton(onPressed: _busy ? null : () => _setStatus(m, StaffStatus.active), child: const Text('Reactivar')),
        ],
        if (canManage || isMe)
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _PasswordDialog(member: m, own: isMe),
            ),
            icon: const Icon(Icons.key_outlined, size: 18),
            label: const Text('Contraseña'),
          ),
        if (!(canManage && !isMe)) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 18,
        children: [
          Row(
            children: [
              _Avatar(m, size: 56),
              const SizedBox(width: 16),
              Expanded(child: Text(m.role.summary, style: AppText.muted)),
            ],
          ),
          Panel(
            title: 'Datos',
            child: Column(
              children: [
                LeaderLine('Cédula', formatDocument(m.documentId).ifEmpty('—')),
                LeaderLine('Teléfono', formatPhone(m.phone).ifEmpty('—')),
                LeaderLine('Correo', m.email ?? '—'),
                LeaderLine('Ingreso', formatDate(m.hiredOn)),
                if (m.terminatedOn != null) LeaderLine('Baja', formatDate(m.terminatedOn!)),
                LeaderLine(
                  'Último acceso a la app',
                  m.lastSignInAt == null ? '—' : '${formatDate(m.lastSignInAt!)} ${formatTime(m.lastSignInAt!)}',
                ),
                if ((m.notes ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(m.notes!, style: AppText.muted),
                  ),
                ],
              ],
            ),
          ),
          Panel(
            title: 'Turno semanal',
            trailing: canManage
                ? TextButton(
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => _ShiftsDialog(member: m, current: shifts),
                    ),
                    child: const Text('Editar'),
                  )
                : null,
            child: shifts.isEmpty
                ? Text('Sin turno asignado.', style: AppText.muted)
                : Column(children: [for (final s in shifts) LeaderLine(s.weekdayName, s.label)]),
          ),
          Panel(
            title: 'Jornadas',
            trailing: Text(
              '${formatWorked(workedInMonth(entries, now, now))} este mes${lateCount > 0 ? ' · $lateCount con retraso' : ''}',
              style: AppText.mono(size: 11.5, color: lateCount > 0 ? AppColors.warning : AppColors.textMuted),
            ),
            child: entries.isEmpty
                ? Text('Todavía no ha marcado entrada.', style: AppText.muted)
                : Column(
                    children: [
                      for (final e in entries.take(14))
                        LeaderLine(
                          '${formatShortDate(e.clockIn)} · ${formatTime(e.clockIn)}–${e.open ? 'en turno' : formatTime(e.clockOut!)}'
                          '${lateMinutes(e, shifts) > 0 ? ' · tarde ${lateMinutes(e, shifts)} min' : ''}',
                          formatWorked(e.worked(now)),
                          color: lateMinutes(e, shifts) > 0 ? AppColors.warning : null,
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Alta y edición

Future<void> showStaffForm(BuildContext context, {StaffMember? member}) => showDialog<void>(
  context: context,
  builder: (_) => _StaffForm(member: member),
);

class _StaffForm extends ConsumerStatefulWidget {
  const _StaffForm({this.member});

  final StaffMember? member;

  @override
  ConsumerState<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends ConsumerState<_StaffForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.member?.fullName);
  late String _nationality = widget.member?.documentId?.startsWith('E') ?? false ? 'E' : 'V';
  late final _doc = TextEditingController(
    text: onlyDigits(widget.member?.documentId).isEmpty ? '' : formatDocument(onlyDigits(widget.member?.documentId)),
  );
  late final _phone = TextEditingController(text: onlyDigits(widget.member?.phone).isEmpty ? '' : formatPhone(widget.member?.phone));
  late final _email = TextEditingController(text: widget.member?.email);
  late final _notes = TextEditingController(text: widget.member?.notes);
  final _password = TextEditingController();
  late StaffRole _role = widget.member?.role ?? StaffRole.reception;
  late DateTime _hiredOn = widget.member?.hiredOn ?? DateTime.now();
  bool _showPassword = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _doc, _phone, _email, _notes, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final docDigits = onlyDigits(_doc.text);
    final input = StaffInput(
      fullName: _name.text.trim(),
      role: _role,
      documentId: docDigits.isEmpty ? null : '$_nationality-$docDigits',
      phone: onlyDigits(_phone.text).isEmpty ? null : onlyDigits(_phone.text),
      email: _email.text.trim().isEmpty ? null : _email.text.trim().toLowerCase(),
      hiredOn: _hiredOn,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    final repo = ref.read(gymRepositoryProvider);
    try {
      if (widget.member == null) {
        await repo.createStaff(NewStaff(input: input, email: input.email!, password: _password.text));
      } else {
        await repo.updateStaff(widget.member!.userId, input);
      }
      ref
        ..invalidate(staffDirectoryProvider)
        ..invalidate(currentStaffProvider)
        ..invalidate(auditLogProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(
        context,
        widget.member == null
            ? '${input.fullName} ya puede entrar con ${input.email} y la contraseña que le diste'
            : 'Datos de ${input.fullName} guardados',
      );
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.member != null;
    final me = ref.watch(currentStaffProvider).value;
    final roles = [
      for (final r in StaffRole.values)
        if (r != StaffRole.owner || me?.role == StaffRole.owner) r,
    ];
    final docField = TextFormField(
      controller: _doc,
      decoration: InputDecoration(
        labelText: 'Cédula',
        hintText: '24.518.330',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _nationality,
              items: [
                for (final n in const ['V', 'E'])
                  DropdownMenuItem(
                    value: n,
                    child: Text('$n-', style: AppText.mono(size: 14)),
                  ),
              ],
              onChanged: (v) => setState(() => _nationality = v!),
            ),
          ),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: const [ThousandsInputFormatter(maxDigits: 9)],
      validator: (v) {
        final d = onlyDigits(v);
        return d.isEmpty || (d.length >= 6 && d.length <= 9) ? null : 'Cédula de 6 a 9 dígitos';
      },
    );
    final phoneField = TextFormField(
      controller: _phone,
      decoration: const InputDecoration(labelText: 'Teléfono', hintText: '0414-555-0192'),
      keyboardType: TextInputType.phone,
      inputFormatters: const [PhoneInputFormatter()],
      validator: (v) {
        final d = onlyDigits(v);
        return d.isEmpty || d.length >= 10 ? null : 'Teléfono incompleto';
      },
    );
    return FormDialog(
      title: editing ? 'Editar persona' : 'Nueva persona',
      subtitle: editing ? widget.member!.fullName : 'Crea su cuenta: entrará con este correo y contraseña',
      width: 560,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(editing ? 'Guardar cambios' : 'Crear cuenta')),
      ],
      child: Form(
        key: _form,
        child: Column(
          spacing: 14,
          children: [
            TextFormField(
              controller: _name,
              autofocus: !context.isPhone,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Ingresa el nombre y apellido' : null,
            ),
            DropdownButtonFormField<StaffRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Rol *'),
              items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(r.label))],
              onChanged: (r) => setState(() => _role = r!),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(_role.summary, style: AppText.muted.copyWith(fontSize: 12.5)),
            ),
            if (context.isPhone) ...[
              docField,
              phoneField,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [
                  Expanded(child: docField),
                  Expanded(child: phoneField),
                ],
              ),
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: editing ? 'Correo' : 'Correo (para entrar) *'),
              keyboardType: TextInputType.emailAddress,
              enabled: !editing || (_email.text.isNotEmpty),
              validator: (v) {
                final t = (v ?? '').trim();
                if (!editing && t.isEmpty) return 'El correo es su usuario para entrar';
                return t.isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'Correo inválido';
              },
            ),
            if (!editing)
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                inputFormatters: [LengthLimitingTextInputFormatter(72)],
                decoration: InputDecoration(
                  labelText: 'Contraseña inicial *',
                  helperText: 'Mínimo 8 caracteres. Dásela en persona; podrá cambiarla en Ajustes.',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Ocultar' : 'Mostrar',
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  ),
                ),
                validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
              ),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _hiredOn,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                );
                if (d != null) setState(() => _hiredOn = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Fecha de ingreso', suffixIcon: Icon(Icons.event_outlined)),
                child: Text(formatDate(_hiredOn)),
              ),
            ),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas', hintText: 'Contacto de emergencia, observaciones…'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Contraseña

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog({required this.member, required this.own});

  final StaffMember member;
  final bool own;

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(gymRepositoryProvider);
      widget.own ? await repo.changeOwnPassword(_password.text) : await repo.setStaffPassword(widget.member.userId, _password.text);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, widget.own ? 'Tu contraseña se cambió' : 'Contraseña de ${widget.member.fullName} cambiada');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FormDialog(
    title: 'Contraseña',
    subtitle: widget.own ? 'Tu cuenta' : widget.member.fullName,
    width: 440,
    actions: [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('Cambiar')),
    ],
    child: Form(
      key: _form,
      child: Column(
        spacing: 14,
        children: [
          TextFormField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            inputFormatters: [LengthLimitingTextInputFormatter(72)],
            decoration: const InputDecoration(labelText: 'Nueva contraseña', helperText: 'Mínimo 8 caracteres'),
            validator: (v) => (v ?? '').length < 8 ? 'Mínimo 8 caracteres' : null,
          ),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Repítela'),
            validator: (v) => v == _password.text ? null : 'No coincide',
            onFieldSubmitted: (_) => _save(),
          ),
        ],
      ),
    ),
  );
}

/// Cambiar la contraseña propia (se usa desde Ajustes).
Future<void> showOwnPasswordDialog(BuildContext context, StaffAccess me) => showDialog<void>(
  context: context,
  builder: (_) => _PasswordDialog(
    member: StaffMember(userId: me.userId, fullName: me.fullName, role: me.role, status: StaffStatus.active, hiredOn: DateTime.now()),
    own: true,
  ),
);

// ---------------------------------------------------------------------------
// Turnos

class _ShiftsDialog extends ConsumerStatefulWidget {
  const _ShiftsDialog({required this.member, required this.current});

  final StaffMember member;
  final List<StaffShift> current;

  @override
  ConsumerState<_ShiftsDialog> createState() => _ShiftsDialogState();
}

class _ShiftsDialogState extends ConsumerState<_ShiftsDialog> {
  late final Map<int, (int, int)?> _days = {
    for (var d = 1; d <= 7; d++)
      d: switch (widget.current.where((s) => s.weekday == d).firstOrNull) {
        final s? => (s.startMinutes, s.endMinutes),
        null => null,
      },
  };
  bool _busy = false;

  Future<int?> _pick(int minutes) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    return t == null ? null : t.hour * 60 + t.minute;
  }

  Future<void> _save() async {
    final shifts = [
      for (final MapEntry(key: d, value: v) in _days.entries)
        if (v != null) StaffShift(weekday: d, startMinutes: v.$1, endMinutes: v.$2),
    ];
    if (shifts.any((s) => s.endMinutes <= s.startMinutes)) {
      showToast(context, 'La salida debe ser después de la entrada', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).saveShifts(widget.member.userId, shifts);
      ref.invalidate(staffShiftsProvider(widget.member.userId));
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Turno de ${widget.member.fullName.split(' ').first} guardado');
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final first = _days.values.whereType<(int, int)>().firstOrNull ?? (6 * 60, 14 * 60);
    return FormDialog(
      title: 'Turno semanal',
      subtitle: widget.member.fullName,
      width: 520,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar turno')),
      ],
      child: Column(
        children: [
          for (var d = 1; d <= 7; d++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 132,
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(StaffShift.weekdayNames[d - 1]),
                      value: _days[d] != null,
                      onChanged: (v) => setState(() => _days[d] = v! ? first : null),
                    ),
                  ),
                  const Spacer(),
                  if (_days[d] case (final start, final end)) ...[
                    TextButton(
                      onPressed: () async {
                        final v = await _pick(start);
                        if (v != null) setState(() => _days[d] = (v, end));
                      },
                      child: Text(StaffShift.hhmm(start), style: AppText.mono(size: 15)),
                    ),
                    const Text('–'),
                    TextButton(
                      onPressed: () async {
                        final v = await _pick(end);
                        if (v != null) setState(() => _days[d] = (start, v));
                      },
                      child: Text(StaffShift.hhmm(end), style: AppText.mono(size: 15)),
                    ),
                  ] else
                    Text('Libre', style: AppText.muted),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Roles y permisos

class _RolesMatrix extends ConsumerStatefulWidget {
  const _RolesMatrix();

  @override
  ConsumerState<_RolesMatrix> createState() => _RolesMatrixState();
}

class _RolesMatrixState extends ConsumerState<_RolesMatrix> {
  final _pending = <(StaffRole, String)>{};

  Future<void> _toggle(StaffRole role, String perm, bool enabled) async {
    setState(() => _pending.add((role, perm)));
    try {
      await ref.read(gymRepositoryProvider).setRolePermission(role, perm, enabled);
      ref
        ..invalidate(rolePermissionsProvider)
        ..invalidate(currentStaffProvider)
        ..invalidate(auditLogProvider);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _pending.remove((role, perm)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(permissionCatalogProvider).value ?? permissionCatalog;
    final roles = ref.watch(rolePermissionsProvider);
    final canEdit = ref.watch(canProvider(Perm.rolesManage));
    return AsyncView(
      roles,
      onRetry: () => ref.invalidate(rolePermissionsProvider),
      data: (map) {
        final groups = <String, List<PermissionInfo>>{};
        for (final p in catalog) {
          (groups[p.module] ??= []).add(p);
        }
        Widget cell(StaffRole role, String perm) {
          if (role == StaffRole.owner) {
            return const Tooltip(message: 'El dueño siempre lo puede todo', child: Icon(Icons.check, size: 20, color: AppColors.ink));
          }
          final on = map[role]?.contains(perm) ?? false;
          if (_pending.contains((role, perm))) {
            return const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2));
          }
          return Checkbox(value: on, onChanged: canEdit ? (v) => _toggle(role, perm, v!) : null);
        }

        const col = 124.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              canEdit
                  ? 'Marca qué puede hacer cada rol. El cambio se aplica al instante a todas sus cuentas, también en el servidor.'
                  : 'Así está repartido el acceso. Solo el dueño puede cambiar estos permisos.',
              style: AppText.muted,
            ),
            const SizedBox(height: 16),
            Panel(
              padding: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: c.maxWidth < 760 ? 760 : c.maxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ink, width: 1.2))),
                          child: Row(
                            children: [
                              Expanded(child: Text('PERMISO', style: AppText.label)),
                              for (final r in StaffRole.values) SizedBox(width: col, child: Center(child: RoleBadge(r))),
                            ],
                          ),
                        ),
                        for (final MapEntry(key: module, value: perms) in groups.entries) ...[
                          Container(
                            color: AppColors.raised,
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                            child: Text(module.toUpperCase(), style: AppText.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600)),
                          ),
                          for (final p in perms)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              height: 46,
                              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                              child: Row(
                                children: [
                                  Expanded(child: Text(p.label, overflow: TextOverflow.ellipsis)),
                                  for (final r in StaffRole.values) SizedBox(width: col, child: Center(child: cell(r, p.code))),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bitácora

class _AuditLog extends ConsumerWidget {
  const _AuditLog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(auditLogProvider);
    return AsyncView(
      log,
      onRetry: () => ref.invalidate(auditLogProvider),
      data: (list) => list.isEmpty
          ? const EmptyState(
              icon: Icons.history,
              title: 'Sin actividad registrada',
              message: 'Aquí aparecen anulaciones, eliminaciones, cambios de precio, de rol y de permisos.',
            )
          : Panel(
              title: 'Últimos ${list.length} movimientos',
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final e in list)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.border)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              '${formatShortDate(e.at)}\n${formatTime(e.at)}',
                              style: AppText.mono(size: 11.5, color: AppColors.textMuted),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 2,
                              children: [
                                Text(e.description, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text(e.userName ?? 'Sistema', style: AppText.mono(size: 11.5, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
