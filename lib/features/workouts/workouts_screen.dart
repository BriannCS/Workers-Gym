// Hecho por Briann$ - Workers Corp.
// Entrenos: el entrenador anota qué trabajó cada cliente (partes del cuerpo,
// tipo de entreno, duración, esfuerzo y notas). Con un cliente elegido se ve
// su equilibrio: cuántos días lleva cada parte sin trabajarse y qué le toca.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../../domain/workouts.dart';

class WorkoutsScreen extends ConsumerStatefulWidget {
  const WorkoutsScreen({super.key});

  @override
  ConsumerState<WorkoutsScreen> createState() => _WorkoutsScreenState();
}

class _WorkoutsScreenState extends ConsumerState<WorkoutsScreen> {
  String? _memberId;
  bool _onlyMine = false;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(ref.watch(clockProvider)());
    final me = ref.watch(currentStaffProvider).value;
    final canEdit = ref.watch(canProvider(Perm.workoutsEdit));
    final members = (ref.watch(membersProvider).value ?? const <Member>[]).where((m) => m.active).toList();
    final all = ref.watch(workoutsProvider);
    final logs = (all.value ?? const <WorkoutLog>[])
        .where((w) => (_memberId == null || w.memberId == _memberId) && (!_onlyMine || w.createdBy == me?.userId))
        .toList();
    final member = members.where((m) => m.id == _memberId).firstOrNull;

    final week = logs.where((w) => today.difference(dateOnly(w.trainedOn)).inDays < 7).toList();
    final scores = ScoreBoard(
      scores: [
        Score(
          label: 'Hoy',
          value: '${logs.where((w) => dateOnly(w.trainedOn) == today).length}',
          caption: 'entrenos anotados',
          color: AppColors.plateBlue,
        ),
        Score(label: 'Últimos 7 días', value: '${week.length}', caption: 'entrenos', color: AppColors.success),
        member == null
            ? Score(label: 'Clientes', value: '${week.map((w) => w.memberId).toSet().length}', caption: 'entrenaron esta semana')
            : Score(
                label: 'Minutos · 7 días',
                value: '${week.fold<int>(0, (s, w) => s + (w.durationMin ?? 0))}',
                caption: member.fullName.split(' ').first,
              ),
      ],
    );

    final filters = Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 340,
          child: DropdownMenu<String?>(
            key: ValueKey(_memberId),
            width: 340,
            initialSelection: _memberId,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            hintText: 'Todos los clientes',
            leadingIcon: const Icon(Icons.search, size: 20),
            onSelected: (id) => setState(() => _memberId = id),
            dropdownMenuEntries: [
              const DropdownMenuEntry(value: null, label: 'Todos los clientes'),
              for (final m in members) DropdownMenuEntry(value: m.id, label: m.fullName),
            ],
          ),
        ),
        if (canEdit)
          FilterChip(label: const Text('Solo los que anoté yo'), selected: _onlyMine, onSelected: (v) => setState(() => _onlyMine = v)),
      ],
    );

    final log = Panel(
      title: member == null ? 'Bitácora' : 'Bitácora de ${member.fullName}',
      padding: EdgeInsets.zero,
      child: AsyncView(
        all,
        onRetry: () => ref.invalidate(workoutsProvider),
        data: (_) => logs.isEmpty
            ? EmptyState(
                icon: Icons.fitness_center,
                title: 'Sin entrenos anotados',
                message: canEdit ? 'Anota lo que trabajó el cliente al terminar su sesión.' : null,
                action: canEdit
                    ? FilledButton(
                        onPressed: () => showWorkoutForm(context, memberId: _memberId),
                        child: const Text('Registrar entreno'),
                      )
                    : null,
              )
            : _WorkoutLogList(logs: logs, members: members, today: today, showMember: member == null),
      ),
    );

    final side = member == null ? _MostWorked(logs: week) : _Balance(member: member, logs: logs, today: today);

    return PageBody(
      header: PageHeader(
        title: 'Entrenos',
        subtitle: 'Lo que trabajó cada cliente',
        actions: [
          if (canEdit)
            FilledButton.icon(
              onPressed: () => showWorkoutForm(context, memberId: _memberId),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar entreno'),
            ),
        ],
      ),
      children: [
        scores,
        const SizedBox(height: 24),
        filters,
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 900
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 20, children: [side, log])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 24,
                  children: [
                    Expanded(flex: 7, child: log),
                    Expanded(flex: 5, child: side),
                  ],
                ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bitácora agrupada por día

class _WorkoutLogList extends StatelessWidget {
  const _WorkoutLogList({required this.logs, required this.members, required this.today, required this.showMember});

  final List<WorkoutLog> logs;
  final List<Member> members;
  final DateTime today;
  final bool showMember;

  String _dayLabel(DateTime d) {
    final diff = today.difference(dateOnly(d)).inDays;
    return switch (diff) {
      0 => 'Hoy',
      1 => 'Ayer',
      _ => formatLongDate(d),
    };
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? day;
    for (final w in logs) {
      final d = dateOnly(w.trainedOn);
      if (d != day) {
        day = d;
        children.add(
          Container(
            color: AppColors.raised,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Text(
              _dayLabel(d).toUpperCase(),
              style: AppText.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      children.add(_WorkoutTile(log: w, member: members.where((m) => m.id == w.memberId).firstOrNull, showMember: showMember));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _WorkoutTile extends ConsumerWidget {
  const _WorkoutTile({required this.log, required this.member, required this.showMember});

  final WorkoutLog log;
  final Member? member;
  final bool showMember;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentStaffProvider).value;
    final mine = log.createdBy == me?.userId;
    final canEdit = (me?.can(Perm.workoutsEdit) ?? false) && (mine || me!.role == StaffRole.owner || me.role == StaffRole.admin);
    final muted = AppText.mono(size: 12, color: AppColors.textMuted);

    final tags = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final p in log.bodyParts) _Tag(p.label, filled: true), for (final t in log.types) _Tag(t.label)],
    );
    final meta = [
      if (log.durationMin != null) '${log.durationMin} min',
      if (log.effort != null) 'esfuerzo ${effortLabels[log.effort! - 1].toLowerCase()}',
      log.trainerName.isEmpty ? null : 'por ${log.trainerName}',
    ].whereType<String>().join(' · ');

    return InkWell(
      onTap: canEdit ? () => showWorkoutForm(context, log: log) : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showMember && member != null) ...[Initials(member!, size: 38), const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 8,
                children: [
                  if (showMember)
                    Text(log.memberName ?? member?.fullName ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  if (log.bodyParts.isNotEmpty || log.types.isNotEmpty) tags,
                  if ((log.notes ?? '').isNotEmpty) Text(log.notes!, style: const TextStyle(height: 1.35)),
                  if (meta.isNotEmpty) Text(meta, style: muted),
                ],
              ),
            ),
            if (log.effort != null) Padding(padding: const EdgeInsets.only(top: 4, left: 8), child: _EffortDots(log.effort!)),
            if (canEdit)
              IconButton(
                tooltip: 'Borrar entreno',
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline, size: 20),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar este entreno?'),
        content: Text('${log.memberName ?? 'Cliente'} · ${formatDate(log.trainedOn)}. No se puede deshacer.'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(gymRepositoryProvider).deleteWorkout(log.id);
      ref.invalidate(workoutsProvider);
      if (context.mounted) showToast(context, 'Entreno borrado');
    } catch (e) {
      if (context.mounted) showToast(context, 'No se pudo borrar: ${friendlyError(e)}', error: true);
    }
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: filled ? AppColors.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      border: Border.all(color: filled ? AppColors.ink : AppColors.borderStrong),
    ),
    child: Text(
      text.toUpperCase(),
      style: AppText.label.copyWith(fontSize: 10, color: filled ? AppColors.surface : AppColors.ink, letterSpacing: .6),
    ),
  );
}

class _EffortDots extends StatelessWidget {
  const _EffortDots(this.effort);

  final int effort;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Esfuerzo: ${effortLabels[effort - 1]}',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        for (var i = 1; i <= 5; i++)
          Container(
            width: 6,
            height: 14,
            decoration: BoxDecoration(color: i <= effort ? _effortColor(effort) : AppColors.border, borderRadius: BorderRadius.circular(1)),
          ),
      ],
    ),
  );
}

Color _effortColor(int e) => switch (e) {
  <= 2 => AppColors.success,
  3 => AppColors.plateBlue,
  4 => AppColors.warning,
  _ => AppColors.danger,
};

// ---------------------------------------------------------------------------
// Panel lateral

/// Con un cliente elegido: días desde que trabajó cada parte y qué le toca.
class _Balance extends StatelessWidget {
  const _Balance({required this.member, required this.logs, required this.today});

  final Member member;
  final List<WorkoutLog> logs;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final since = daysSinceWorked(logs, today);
    // Le toca: primero lo que más días lleva sin trabajarse (4+), luego lo
    // que nunca se ha anotado.
    final overdue = BodyPart.specific.where((p) => (since[p] ?? -1) >= 4).toList()..sort((a, b) => since[b]!.compareTo(since[a]!));
    final never = BodyPart.specific.where((p) => since[p] == null);
    final suggestion = [for (final p in overdue) '${p.label} (${since[p]} d)', for (final p in never) p.label].take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 20,
      children: [
        if (logs.isNotEmpty)
          StickyNote(
            title: 'Le toca',
            child: Text(
              suggestion.isEmpty ? 'Viene equilibrado: todo trabajado en los últimos 3 días.' : suggestion.join(' · '),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Color(0xFF17140F)),
            ),
          ),
        Panel(
          title: 'Equilibrio muscular',
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final zone in [BodyZone.upper, BodyZone.core, BodyZone.lower]) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(zone.label.toUpperCase(), style: AppText.label),
                ),
                for (final p in BodyPart.specific.where((p) => p.zone == zone)) _BalanceRow(part: p, days: since[p]),
              ],
              const SizedBox(height: 10),
              Text('Según los últimos 120 días de entrenos anotados.', style: AppText.muted.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.part, required this.days});

  final BodyPart part;
  final int? days;

  @override
  Widget build(BuildContext context) {
    final d = days;
    final color = d == null
        ? AppColors.borderStrong
        : d <= 3
        ? AppColors.success
        : d <= 7
        ? AppColors.warning
        : AppColors.danger;
    // Barra llena = recién trabajado; se vacía en 14 días.
    final fill = d == null ? 0.0 : (1 - d / 14).clamp(.06, 1.0);
    final label = d == null ? 'nunca' : (d == 0 ? 'hoy' : (d == 1 ? 'ayer' : 'hace $d d'));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 112, child: Text(part.label, overflow: TextOverflow.ellipsis)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Stack(
                children: [
                  Container(height: 10, color: AppColors.raised),
                  FractionallySizedBox(
                    widthFactor: fill,
                    child: Container(height: 10, color: color),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 74,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: AppText.mono(size: 12, color: d == null ? AppColors.textMuted : color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sin cliente elegido: qué se trabajó más en la semana (todo el gimnasio).
class _MostWorked extends StatelessWidget {
  const _MostWorked({required this.logs});

  final List<WorkoutLog> logs;

  @override
  Widget build(BuildContext context) {
    final count = {for (final p in BodyPart.specific) p: 0};
    for (final l in logs) {
      for (final p in l.worked) {
        count[p] = count[p]! + 1;
      }
    }
    final top = count.values.fold(0, (a, b) => a > b ? a : b);
    final sorted = count.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Panel(
      title: 'Lo más trabajado · 7 días',
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      child: logs.isEmpty
          ? Text('Aún no hay entrenos esta semana.', style: AppText.muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final MapEntry(key: p, value: n) in sorted)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 112, child: Text(p.label, overflow: TextOverflow.ellipsis)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: Stack(
                              children: [
                                Container(height: 10, color: AppColors.raised),
                                FractionallySizedBox(
                                  widthFactor: top == 0 ? 0 : n / top,
                                  child: Container(height: 10, color: AppColors.plateBlue),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: Text('$n', textAlign: TextAlign.right, style: AppText.mono(size: 12)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Text('Elige un cliente para ver su equilibrio y qué le toca.', style: AppText.muted.copyWith(fontSize: 12)),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formulario

Future<void> showWorkoutForm(BuildContext context, {WorkoutLog? log, String? memberId}) => showDialog(
  context: context,
  builder: (_) => _WorkoutForm(log: log, memberId: memberId),
);

class _WorkoutForm extends ConsumerStatefulWidget {
  const _WorkoutForm({this.log, this.memberId});

  final WorkoutLog? log;
  final String? memberId;

  @override
  ConsumerState<_WorkoutForm> createState() => _WorkoutFormState();
}

class _WorkoutFormState extends ConsumerState<_WorkoutForm> {
  late String? _memberId = widget.log?.memberId ?? widget.memberId;
  late DateTime _day = dateOnly(widget.log?.trainedOn ?? ref.read(clockProvider)());
  late final _parts = <BodyPart>{...?widget.log?.bodyParts};
  late final _types = <WorkoutType>{...?widget.log?.types};
  late int? _effort = widget.log?.effort;
  late final _minutes = TextEditingController(text: widget.log?.durationMin?.toString() ?? '');
  late final _notes = TextEditingController(text: widget.log?.notes ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _minutes.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final today = dateOnly(ref.read(clockProvider)());
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(_day.year, _day.month, _day.day),
      firstDate: DateTime(today.year, today.month, today.day - 90),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (d != null) setState(() => _day = dateOnly(d));
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutes.text);
    final input = WorkoutInput(
      memberId: _memberId ?? '',
      trainedOn: _day,
      bodyParts: [
        for (final p in BodyPart.values)
          if (_parts.contains(p)) p,
      ],
      types: [
        for (final t in WorkoutType.values)
          if (_types.contains(t)) t,
      ],
      durationMin: minutes == null || minutes <= 0 ? null : minutes,
      effort: _effort,
      notes: _notes.text,
    );
    if (_memberId == null) return setState(() => _error = 'Elige el cliente');
    if (!input.hasContent) return setState(() => _error = 'Marca al menos una parte del cuerpo, un tipo de entreno o escribe una nota');
    if (minutes != null && minutes > 600) return setState(() => _error = 'La duración máxima es 600 minutos');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(gymRepositoryProvider).saveWorkout(input, id: widget.log?.id);
      ref.invalidate(workoutsProvider);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, widget.log == null ? 'Entreno registrado' : 'Entreno actualizado');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final members = (ref.watch(membersProvider).value ?? const <Member>[]).where((m) => m.active || m.id == _memberId).toList();
    final today = dateOnly(ref.watch(clockProvider)());
    final dayLabel = _day == today ? 'Hoy' : (today.difference(_day).inDays == 1 ? 'Ayer' : formatDate(_day));

    Widget section(String label) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: AppText.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600),
      ),
    );

    return FormDialog(
      title: widget.log == null ? 'Registrar entreno' : 'Editar entreno',
      subtitle: 'Lo que trabajó el cliente en la sesión',
      width: 640,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final picker = DropdownMenu<String>(
                width: c.maxWidth < 480 ? c.maxWidth : c.maxWidth - 172,
                initialSelection: _memberId,
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 300,
                label: const Text('Cliente *'),
                leadingIcon: const Icon(Icons.search, size: 20),
                onSelected: (id) => setState(() => _memberId = id),
                dropdownMenuEntries: [
                  for (final m in members)
                    DropdownMenuEntry(
                      value: m.id,
                      label: m.documentId == null ? m.fullName : '${m.fullName} · ${formatDocument(m.documentId)}',
                    ),
                ],
              );
              final date = OutlinedButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text(dayLabel),
                style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
              );
              return c.maxWidth < 480
                  ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [picker, date])
                  : Row(spacing: 12, children: [picker, date]);
            },
          ),
          section('Partes del cuerpo'),
          for (final zone in BodyZone.values) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 2),
              child: Text(zone.label, style: AppText.muted.copyWith(fontSize: 12)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in BodyPart.values.where((p) => p.zone == zone))
                    FilterChip(
                      label: Text(p.label),
                      selected: _parts.contains(p),
                      onSelected: (v) => setState(() => v ? _parts.add(p) : _parts.remove(p)),
                    ),
                ],
              ),
            ),
          ],
          section('Tipo de entreno'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in WorkoutType.values)
                FilterChip(
                  label: Text(t.label),
                  selected: _types.contains(t),
                  onSelected: (v) => setState(() => v ? _types.add(t) : _types.remove(t)),
                ),
            ],
          ),
          section('Duración y esfuerzo'),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 130,
                child: TextField(
                  controller: _minutes,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsOnly,
                  decoration: const InputDecoration(labelText: 'Minutos', suffixText: 'min'),
                ),
              ),
              SegmentedButton<int>(
                segments: [for (var i = 1; i <= 5; i++) ButtonSegment(value: i, label: Text('$i'), tooltip: effortLabels[i - 1])],
                selected: {?_effort},
                emptySelectionAllowed: true,
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _effort = s.firstOrNull),
              ),
              Text(_effort == null ? 'Esfuerzo (opcional)' : effortLabels[_effort! - 1], style: AppText.muted),
            ],
          ),
          section('Notas'),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: const InputDecoration(hintText: 'Ejercicios, series, cargas, molestias, próximos objetivos…'),
          ),
          if (_error != null)
            Text(
              _error!,
              style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}
