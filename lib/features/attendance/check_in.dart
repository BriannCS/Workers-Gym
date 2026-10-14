// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';

/// Registra la entrada y avisa si la membresía no está al día. La entrada se
/// guarda igual: recepción decide si deja pasar o cobra primero.
Future<bool> checkInMember(BuildContext context, WidgetRef ref, Member member) async {
  final today = ref.read(clockProvider)();
  try {
    await ref.read(gymRepositoryProvider).checkIn(member.id);
    ref
      ..invalidate(todayAttendanceProvider)
      ..invalidate(membersProvider);
    if (!context.mounted) return true;
    final status = member.status(today);
    final firstName = member.fullName.split(' ').first;
    switch (status) {
      case MembershipStatus.active || MembershipStatus.expiringSoon:
        showToast(context, 'Entrada registrada: $firstName');
      case MembershipStatus.expired || MembershipStatus.none:
        showToast(context, 'Entrada registrada, pero $firstName no tiene la membresía al día', error: true);
    }
    return true;
  } catch (e) {
    if (context.mounted) showToast(context, 'No se pudo registrar la entrada: ${friendlyError(e)}', error: true);
    return false;
  }
}
