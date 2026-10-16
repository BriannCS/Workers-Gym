// Hecho por Briann$ - Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/demo_gym_repository.dart';
import '../../data/gym_repository.dart';
import '../../domain/staff.dart';
import '../formatters.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Marcar entrada / salida del personal con la hora del servidor.
class ClockButton extends ConsumerStatefulWidget {
  const ClockButton({super.key, this.onSpine = false, this.compact = false});

  final bool onSpine;
  final bool compact;

  @override
  ConsumerState<ClockButton> createState() => _ClockButtonState();
}

class _ClockButtonState extends ConsumerState<ClockButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final entry = await ref.read(gymRepositoryProvider).clockInOut();
      ref
        ..invalidate(staffTimeEntriesProvider)
        ..invalidate(staffDirectoryProvider);
      if (mounted) {
        showToast(
          context,
          entry.open
              ? 'Entrada marcada a las ${formatTime(entry.clockIn)}'
              : 'Salida marcada a las ${formatTime(entry.clockOut!)} · ${formatWorked(entry.worked(entry.clockOut!))}',
        );
      }
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo marcar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentStaffProvider).value == null) return const SizedBox.shrink();
    final open = ref.watch(myOpenShiftProvider).value;
    final onShift = open != null;
    final fg = widget.onSpine ? AppColors.onSpine : AppColors.ink;
    final label = onShift ? 'Marcar salida' : 'Marcar entrada';
    final icon = onShift ? Icons.logout : Icons.login;

    if (widget.compact) {
      return IconButton(
        tooltip: onShift ? 'En turno desde las ${formatTime(open.clockIn)} · $label' : label,
        onPressed: _busy ? null : _toggle,
        icon: Icon(icon, size: 20, color: onShift ? AppColors.success : fg.withValues(alpha: .8)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: onShift ? AppColors.success : fg.withValues(alpha: .35), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                onShift ? 'EN TURNO DESDE ${formatTime(open.clockIn)}' : 'FUERA DE TURNO',
                style: AppText.label.copyWith(color: fg.withValues(alpha: .75), fontSize: 9.5),
              ),
            ),
          ],
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _toggle,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            side: BorderSide(color: fg.withValues(alpha: .35)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          icon: Icon(icon, size: 16),
          label: Text(label),
        ),
      ],
    );
  }
}

/// "8 h 15 min".
String formatWorked(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : '$h h ${m.toString().padLeft(2, '0')} min';
}

/// Solo en modo demo: cambia de persona para ver la app como cada rol.
class DemoRoleSwitcher extends ConsumerWidget {
  const DemoRoleSwitcher({super.key, this.onSpine = false});

  final bool onSpine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(gymRepositoryProvider);
    if (repo is! DemoGymRepository) return const SizedBox.shrink();
    final me = ref.watch(currentStaffProvider).value;
    final fg = onSpine ? AppColors.onSpine : AppColors.ink;
    return PopupMenuButton<StaffRole>(
      tooltip: 'Probar como otro rol',
      onSelected: (role) {
        repo.actAs(role);
        refreshGymData(ref);
        context.go('/');
      },
      itemBuilder: (_) => [for (final r in StaffRole.values) CheckedPopupMenuItem(value: r, checked: me?.role == r, child: Text(r.label))],
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.badge_outlined, size: 16, color: fg.withValues(alpha: .75)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'DEMO · ${(me?.role.label ?? '').toUpperCase()}',
                style: AppText.label.copyWith(color: fg.withValues(alpha: .75), fontSize: 9.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.unfold_more, size: 16, color: fg.withValues(alpha: .6)),
          ],
        ),
      ),
    );
  }
}

/// Pantalla para una sección a la que el rol no tiene acceso (por ejemplo, si
/// alguien entra por la URL).
class NotAllowed extends StatelessWidget {
  const NotAllowed({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: EmptyState(
        icon: Icons.lock_outline,
        title: 'Sin acceso a esta sección',
        message: 'Tu rol no incluye este módulo. Si lo necesitas, pídeselo al dueño o al administrador.',
        action: FilledButton(onPressed: () => context.go('/'), child: const Text('Ir al inicio')),
      ),
    ),
  );
}
