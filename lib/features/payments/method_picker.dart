// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../data/rates.dart';
import '../../domain/models.dart';

/// Métodos de pago activos (los de Ajustes) como fichas. Cada una indica si
/// se cobra en dólares o en bolívares.
class MethodPicker extends ConsumerWidget {
  const MethodPicker({super.key, required this.selected, required this.onChanged});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = activeMethods(ref);
    if (methods.isEmpty) {
      return Text('No hay métodos de pago activos. Agrégalos en Ajustes.', style: AppText.muted.copyWith(color: AppColors.warning));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final m in methods)
          ChoiceChip(
            selected: selected?.code == m.code,
            onSelected: (_) => onChanged(m),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(m.name),
                const SizedBox(width: 6),
                Text(
                  m.currency.symbol,
                  style: AppText.mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: selected?.code == m.code ? AppColors.plateYellow : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

List<PaymentMethod> activeMethods(WidgetRef ref) =>
    (ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[]).where((m) => m.active).toList();

/// Si el método es en bolívares: tasa vigente y monto en Bs. Si no hay tasa
/// (sin conexión y sin tasa manual) lo dice y ofrece ir a Ajustes.
class BolivarCharge extends ConsumerWidget {
  const BolivarCharge({super.key, required this.usdCents, required this.method});

  final int usdCents;
  final PaymentMethod? method;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (method == null || !method!.inBolivares) return const SizedBox.shrink();
    final rate = ref.watch(currentRateProvider);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: switch (rate) {
        AsyncValue(value: final r?, hasValue: true) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LeaderLine('Tasa ${r.source.label}', 'Bs. ${formatRate(r.value)}', color: AppColors.textMuted),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('EN BOLÍVARES', style: AppText.label.copyWith(color: AppColors.ink)),
                const Spacer(),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(formatVes(r.vesCents(usdCents)), style: AppText.score(34, color: AppColors.plateBlue)),
                  ),
                ),
              ],
            ),
          ],
        ),
        AsyncValue(hasValue: true) || AsyncError() => Row(
          children: [
            Expanded(
              child: Text(
                'No hay tasa disponible (sin conexión). Usa una tasa manual en Ajustes para cobrar en bolívares.',
                style: AppText.muted.copyWith(color: AppColors.danger),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).popUntil((r) => r.isFirst);
                context.go('/ajustes');
              },
              child: const Text('Ajustes'),
            ),
          ],
        ),
        _ => Text('Consultando tasa del día…', style: AppText.mono(size: 12, color: AppColors.textMuted)),
      },
    );
  }
}

/// Texto del botón de cobro según la moneda del método.
String chargeLabel(int usdCents, PaymentMethod? method, ExchangeRate? rate) => method != null && method.inBolivares && rate != null
    ? 'Cobrar ${formatVes(rate.vesCents(usdCents))}'
    : 'Cobrar ${formatMoney(usdCents)}';
