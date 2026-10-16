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

/// Tarjeta de quien tiene la sesión, al pie del menú: iniciales con un punto
/// de estado (verde = en turno), nombre, rol y un botón pequeño para marcar
/// entrada o salida. Al tocarla se abre su menú (mi cuenta, rol demo, salir).
class StaffCard extends ConsumerStatefulWidget {
  const StaffCard({super.key, this.onSpine = false, this.compact = false});

  final bool onSpine;

  /// Solo las iniciales (menú contraído): marcar va dentro del menú.
  final bool compact;

  @override
  ConsumerState<StaffCard> createState() => _StaffCardState();
}

enum _CardAction { clock, account, signOut }

class _StaffCardState extends ConsumerState<StaffCard> {
  bool _busy = false;

  Future<void> _toggleShift() async {
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

  Future<void> _openMenu(StaffAccess me, bool onShift) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    // Se ancla al borde derecho de la tarjeta (al lado del menú lateral) y
    // showMenu la sube lo necesario para que quepa en la pantalla.
    final topRight = box.localToGlobal(Offset(box.size.width + 8, 0), ancestor: overlay);
    final repo = ref.read(gymRepositoryProvider);
    final supabase = ref.read(supabaseClientProvider);
    final picked = await showMenu<Object>(
      context: context,
      position: RelativeRect.fromRect(topRight & Size(1, box.size.height), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: _CardAction.clock,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(onShift ? Icons.logout : Icons.login, color: onShift ? AppColors.success : null),
            title: Text(onShift ? 'Marcar salida' : 'Marcar entrada'),
          ),
        ),
        const PopupMenuItem(
          value: _CardAction.account,
          child: ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.manage_accounts_outlined), title: Text('Mi cuenta')),
        ),
        if (repo is DemoGymRepository) ...[
          const PopupMenuDivider(),
          PopupMenuItem(enabled: false, height: 28, child: Text('PROBAR COMO', style: AppText.label)),
          for (final r in StaffRole.values) CheckedPopupMenuItem(value: r, checked: me.role == r, child: Text(r.label)),
        ],
        if (supabase != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _CardAction.signOut,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout, color: AppColors.danger),
              title: Text('Cerrar sesión', style: TextStyle(color: AppColors.danger)),
            ),
          ),
        ],
      ],
    );
    if (!mounted || picked == null) return;
    switch (picked) {
      case _CardAction.clock:
        await _toggleShift();
      case _CardAction.account:
        context.go('/ajustes');
      case _CardAction.signOut:
        await supabase?.auth.signOut();
      case StaffRole role when repo is DemoGymRepository:
        repo.actAs(role);
        refreshGymData(ref);
        context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentStaffProvider).value;
    if (me == null) return const SizedBox.shrink();
    final open = ref.watch(myOpenShiftProvider).value;
    final onShift = open != null;
    final fg = widget.onSpine ? AppColors.onSpine : AppColors.ink;
    final dim = fg.withValues(alpha: .6);
    final initials = me.fullName.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();

    final avatar = SizedBox.square(
      dimension: 38,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: fg.withValues(alpha: .35)),
            ),
            child: Text(initials, style: AppText.score(17, color: fg)),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: onShift ? AppColors.success : AppColors.borderStrong,
                border: Border.all(color: widget.onSpine ? AppColors.spine : AppColors.surface, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
    final status = onShift ? 'En turno desde las ${formatTime(open.clockIn)}' : 'Fuera de turno';

    if (widget.compact) {
      return Tooltip(
        message: '${me.fullName} · $status',
        child: InkWell(customBorder: const CircleBorder(), onTap: () => _openMenu(me, onShift), child: avatar),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => _openMenu(me, onShift),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      me.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      onShift ? '${me.role.label.toUpperCase()} · EN TURNO ${formatTime(open.clockIn)}' : me.role.label.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(color: onShift ? AppColors.success : dim, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _ShiftToggle(onShift: onShift, busy: _busy, fg: fg, onTap: _toggleShift),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón redondo de marcaje: "entrar" con borde tenue o "salir" en verde.
class _ShiftToggle extends StatelessWidget {
  const _ShiftToggle({required this.onShift, required this.busy, required this.fg, required this.onTap});

  final bool onShift;
  final bool busy;
  final Color fg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = onShift ? AppColors.success : fg.withValues(alpha: .75);
    return Tooltip(
      message: onShift ? 'Marcar salida' : 'Marcar entrada',
      child: InkResponse(
        onTap: busy ? null : onTap,
        radius: 22,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: onShift ? AppColors.success.withValues(alpha: .16) : Colors.transparent,
            border: Border.all(color: onShift ? AppColors.success : fg.withValues(alpha: .3)),
          ),
          child: busy
              ? Padding(
                  padding: const EdgeInsets.all(9),
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Icon(onShift ? Icons.logout : Icons.login, size: 16, color: color),
        ),
      ),
    );
  }
}

/// "8 h 15 min".
String formatWorked(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  return h == 0 ? '$m min' : '$h h ${m.toString().padLeft(2, '0')} min';
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
