// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import 'member_dialogs.dart';

/// Acciones de un cliente: editar, activar/desactivar y eliminar. Se abre al
/// mantener presionada su ficha (teléfono), con clic derecho (PC) o con el
/// botón de opciones de su ficha.
Future<void> showMemberActions(BuildContext context, Member member) {
  // Contexto que sobrevive aunque la fila desaparezca (al eliminar).
  final host = Navigator.of(context, rootNavigator: true).context;
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => _MemberActionsSheet(member: member, host: host),
  );
}

class _MemberActionsSheet extends ConsumerWidget {
  const _MemberActionsSheet({required this.member, required this.host});

  final Member member;
  final BuildContext host;

  Future<void> _toggleActive(WidgetRef ref) async {
    final repo = ref.read(gymRepositoryProvider);
    final container = ProviderScope.containerOf(host, listen: false);
    final firstName = member.fullName.split(' ').first;
    try {
      await repo.setMemberActive(member.id, !member.active);
      container.invalidate(membersProvider);
      if (host.mounted) {
        showToast(host, member.active ? '$firstName quedó inactivo' : '$firstName está activo de nuevo');
      }
    } catch (e) {
      if (host.mounted) showToast(host, 'No se pudo cambiar el estado: ${friendlyError(e)}', error: true);
    }
  }

  Future<void> _delete(WidgetRef ref) async {
    final repo = ref.read(gymRepositoryProvider);
    final container = ProviderScope.containerOf(host, listen: false);
    final ok = await showDialog<bool>(context: host, builder: (_) => _ConfirmDelete(member: member));
    if (ok != true) return;
    try {
      await repo.deleteMember(member);
      container
        ..invalidate(membersProvider)
        ..invalidate(memberPhotosProvider);
      if (host.mounted) showToast(host, '${member.fullName} fue eliminado');
    } catch (e) {
      if (host.mounted) showToast(host, 'No se pudo eliminar: ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider)();
    void run(Future<void> Function() action) {
      Navigator.pop(context);
      action();
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Initials(member, size: 44, status: member.status(today)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(member.fullName.toUpperCase(), style: AppText.score(24), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          member.documentId == null ? 'Sin cédula' : formatDocument(member.documentId),
                          style: AppText.mono(size: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(member.status(today)),
                ],
              ),
            ),
            Container(height: 3, color: AppColors.ink),
            _ActionTile(
              icon: Icons.edit_outlined,
              label: 'Editar datos',
              onTap: () => run(() => showMemberForm(host, member: member)),
            ),
            _ActionTile(
              icon: member.active ? Icons.pause_circle_outline : Icons.play_circle_outline,
              label: member.active ? 'Marcar como inactivo' : 'Marcar como activo',
              detail: member.active ? 'Deja de contar en vencidos y por vencer' : 'Vuelve a la planilla de activos',
              onTap: () => run(() => _toggleActive(ref)),
            ),
            _ActionTile(
              icon: Icons.delete_outline,
              label: 'Eliminar cliente',
              detail: 'Sus pagos y asistencias se conservan en caja',
              color: AppColors.danger,
              onTap: () => run(() => _delete(ref)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.detail, this.color});

  final IconData icon;
  final String label;
  final String? detail;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.ink;
    return ListTile(
      leading: Icon(icon, color: c),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: c)),
      subtitle: detail == null ? null : Text(detail!, style: AppText.muted.copyWith(fontSize: 12.5)),
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
    );
  }
}

class _ConfirmDelete extends StatelessWidget {
  const _ConfirmDelete({required this.member});

  final Member member;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('¿ELIMINAR A ${member.fullName.toUpperCase()}?', style: AppText.score(26)),
      content: const Text(
        'Sale de la planilla y no podrá registrar entradas ni pagos. '
        'Sus pagos, ventas y asistencias se conservan en la caja y el historial.\n\n'
        'Si solo dejó de venir, mejor márcalo como inactivo.',
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: AppColors.surface),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Eliminar'),
        ),
      ],
    );
  }
}
