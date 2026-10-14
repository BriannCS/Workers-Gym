// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../data/rates.dart';
import '../../domain/models.dart';

/// Ajustes: apariencia (por dispositivo), tasa de cambio y métodos de pago
/// (compartidos: los ve igual la PC de recepción y el teléfono).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageBody(
      header: const PageHeader(title: 'Ajustes', subtitle: 'Apariencia, tasa de cambio y métodos de pago'),
      children: [
        LayoutBuilder(builder: (context, c) {
          const rate = _RateSection();
          const methods = _MethodsSection();
          const look = _AppearanceSection();
          if (c.maxWidth < 980) return const Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 28, children: [rate, methods, look]);
          return const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 28,
            children: [
              Expanded(flex: 6, child: rate),
              Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 28, children: [methods, look])),
            ],
          );
        }),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Apariencia

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeModeProvider);
    Widget option({required bool forDark, required String title, required String text}) {
      final selected = dark == forDark;
      return Expanded(
        child: Material(
          color: forDark ? const Color(0xFF15130F) : const Color(0xFFF2EEE5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radius),
            side: BorderSide(color: selected ? AppColors.plateBlue : AppColors.border, width: selected ? 2.5 : 1),
          ),
          child: InkWell(
            onTap: selected ? null : () => ref.read(themeModeProvider.notifier).toggle(),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(forDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: forDark ? const Color(0xFFF0EBE0) : const Color(0xFF17140F)),
                  const SizedBox(height: 10),
                  Text(title.toUpperCase(), style: AppText.score(22, color: forDark ? const Color(0xFFF0EBE0) : const Color(0xFF17140F))),
                  Text(text, style: TextStyle(fontSize: 12, color: forDark ? const Color(0xFFA89E8D) : const Color(0xFF5E574C))),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Panel(
      title: 'Apariencia · este dispositivo',
      child: Row(
        spacing: 12,
        children: [
          option(forDark: false, title: 'Claro', text: 'Papel y tinta'),
          option(forDark: true, title: 'Oscuro', text: 'Pizarra y tiza'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tasa de cambio

class _RateSection extends ConsumerStatefulWidget {
  const _RateSection();

  @override
  ConsumerState<_RateSection> createState() => _RateSectionState();
}

class _RateSectionState extends ConsumerState<_RateSection> {
  final _manual = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _save(GymSettings next) async {
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).saveSettings(next);
      ref.invalidate(settingsProvider);
      if (mounted) showToast(context, 'Ahora se cobra con la tasa ${next.rateSource.label}');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo guardar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const GymSettings();
    final fetched = ref.watch(exchangeRatesProvider);
    final rates = fetched.value ?? const <RateSource, ExchangeRate>{};
    if (_manual.text.isEmpty && settings.manualRate != null) _manual.text = settings.manualRate!.toStringAsFixed(2);

    Widget card(RateSource source) {
      final selected = settings.rateSource == source;
      final rate = rates[source];
      return Material(
        color: selected ? AppColors.ink : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: const BorderSide(color: AppColors.ink, width: 1.3),
        ),
        child: InkWell(
          onTap: selected || _busy || rate == null
              ? null
              : () => _save(GymSettings(rateSource: source, manualRate: settings.manualRate)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(source.label.toUpperCase(), style: AppText.label.copyWith(color: selected ? AppColors.surface : AppColors.ink)),
                    ),
                    if (selected) const Icon(Icons.check_circle, size: 18, color: AppColors.plateYellow),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  rate == null ? (fetched.isLoading ? '…' : 'Sin datos') : formatRate(rate.value),
                  style: AppText.score(32, color: selected ? AppColors.surface : AppColors.ink),
                ),
                Text(
                  rate?.updatedAt == null ? 'Bs. por ${source == RateSource.bcvEur ? 'euro' : 'dólar'}' : 'Act. ${formatShortDate(rate!.updatedAt!)} ${formatTime(rate.updatedAt!)}',
                  style: AppText.mono(size: 11, color: selected ? AppColors.plateYellow : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final manualSelected = settings.rateSource == RateSource.manual;
    return Panel(
      title: 'Tasa de cambio para cobrar en bolívares',
      trailing: TextButton.icon(
        onPressed: () => ref.invalidate(exchangeRatesProvider),
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text('Actualizar'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Los precios están en dólares. Al cobrar con un método en bolívares se multiplica por la tasa elegida, '
            'y esa tasa queda guardada en el pago. Fuente: ve.dolarapi.com.',
            style: AppText.muted,
          ),
          const SizedBox(height: 16),
          ResponsiveGrid(
            minItemWidth: 150,
            spacing: 12,
            children: [for (final s in [RateSource.bcvUsd, RateSource.bcvEur, RateSource.paralelo]) card(s)],
          ),
          if (fetched.hasValue && rates.isEmpty) ...[
            const SizedBox(height: 10),
            Text('No se pudo consultar la API (¿sin conexión?). Puedes usar una tasa manual.', style: AppText.muted.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: manualSelected ? AppColors.plateBlue : AppColors.border, width: manualSelected ? 2 : 1),
              borderRadius: BorderRadius.circular(AppTheme.radius),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                Expanded(
                  child: TextField(
                    controller: _manual,
                    decoration: InputDecoration(
                      labelText: manualSelected ? 'Tasa manual (en uso)' : 'Tasa manual',
                      prefixText: 'Bs. ',
                      helperText: 'Para cobrar sin conexión o con una tasa propia',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [MoneyInputFormatter(decimals: 4)],
                  ),
                ),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          final cents = parseMoney(_manual.text);
                          if (cents == null || cents <= 0) {
                            showToast(context, 'Escribe una tasa mayor que cero', error: true);
                            return;
                          }
                          final value = double.parse(_manual.text.replaceAll(',', '.'));
                          _save(GymSettings(rateSource: RateSource.manual, manualRate: value));
                        },
                  child: Text(manualSelected ? 'Actualizar' : 'Usar manual'),
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
// Métodos de pago

class _MethodsSection extends ConsumerStatefulWidget {
  const _MethodsSection();

  @override
  ConsumerState<_MethodsSection> createState() => _MethodsSectionState();
}

class _MethodsSectionState extends ConsumerState<_MethodsSection> {
  final _name = TextEditingController();
  Currency _currency = Currency.ves;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(paymentMethodsProvider);
      if (mounted) showToast(context, done);
    } catch (e) {
      if (mounted) showToast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.read(gymRepositoryProvider);
    final all = ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final active = all.where((m) => m.active).toList();
    final removed = all.where((m) => !m.active).toList();

    Widget row(PaymentMethod m) => Container(
          padding: const EdgeInsets.fromLTRB(4, 6, 0, 6),
          decoration: const BoxDecoration(border: rowRule),
          child: Row(
            children: [
              Container(
                width: 34,
                padding: const EdgeInsets.symmetric(vertical: 2),
                alignment: Alignment.center,
                color: m.inBolivares ? AppColors.plateBlue : AppColors.plateGreen,
                child: Text(m.currency.symbol, style: AppText.mono(size: 11, weight: FontWeight.w600, color: AppColors.surface)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  m.name,
                  style: TextStyle(fontWeight: FontWeight.w600, color: m.active ? null : AppColors.textMuted),
                ),
              ),
              if (m.active)
                TextButton(
                  onPressed: _busy || active.length == 1 ? null : () => _run(() => repo.setPaymentMethodActive(m.code, false), '${m.name} quitado'),
                  child: const Text('Quitar'),
                )
              else
                TextButton(
                  onPressed: _busy ? null : () => _run(() => repo.setPaymentMethodActive(m.code, true), '${m.name} restaurado'),
                  child: const Text('Restaurar'),
                ),
            ],
          ),
        );

    return Panel(
      title: 'Métodos de pago · ${active.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final m in active) row(m),
          const SizedBox(height: 16),
          Text('AGREGAR MÉTODO', style: AppText.label),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(hintText: 'Ej. Pago móvil BDV, PayPal'),
            onSubmitted: (_) => _add(repo),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ChoiceChip(label: const Text('En dólares'), selected: _currency == Currency.usd, onSelected: (_) => setState(() => _currency = Currency.usd)),
              ChoiceChip(label: const Text('En bolívares'), selected: _currency == Currency.ves, onSelected: (_) => setState(() => _currency = Currency.ves)),
              FilledButton.icon(
                onPressed: _busy ? null : () => _add(repo),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar'),
              ),
            ],
          ),
          if (removed.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('QUITADOS · SE CONSERVAN EN EL HISTORIAL', style: AppText.label),
            for (final m in removed) row(m),
          ],
        ],
      ),
    );
  }

  void _add(GymRepository repo) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      showToast(context, 'Escribe el nombre del método', error: true);
      return;
    }
    _run(() async {
      await repo.addPaymentMethod(name, _currency);
      _name.clear();
    }, '$name agregado');
  }
}
