// Hecho por Briann$ Workers Corp.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';

class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider);
    final today = ref.watch(clockProvider)();
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    int activeOn(Plan p) => members
        .where((m) => m.planName == p.name && m.status(today) != MembershipStatus.expired && m.status(today) != MembershipStatus.none)
        .length;

    return PageBody(
      header: PageHeader(
        title: 'Planes',
        subtitle: 'Membresías que se pueden cobrar',
        actions: [
          FilledButton.icon(
            onPressed: () => _showPlanForm(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Nuevo plan'),
          ),
        ],
      ),
      children: [
        AsyncView(
          plans,
          onRetry: () => ref.invalidate(plansProvider),
          data: (list) => list.isEmpty
              ? Panel(
                  child: EmptyState(
                    icon: Icons.style_outlined,
                    title: 'Sin planes',
                    message: 'Crea al menos un plan para poder registrar pagos.',
                    action: FilledButton(onPressed: () => _showPlanForm(context), child: const Text('Nuevo plan')),
                  ),
                )
              : ResponsiveGrid(
                  minItemWidth: 270,
                  spacing: 20,
                  children: [
                    for (final (i, p) in list.indexed) _MembershipCard(plan: p, activeMembers: activeOn(p), stripe: _stripes[i % _stripes.length]),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Colores de disco para distinguir los carnés entre sí.
const _stripes = [AppColors.plateBlue, AppColors.plateRed, AppColors.plateYellow, AppColors.plateGreen];

/// Plan como carné de membresía: franja del color de un disco, perforación
/// de llavero y el precio como cifra de marcador.
class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.plan, required this.activeMembers, required this.stripe});

  final Plan plan;
  final int activeMembers;
  final Color stripe;

  @override
  Widget build(BuildContext context) {
    final days = plan.durationDays;
    return Opacity(
      opacity: plan.active ? 1 : .5,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.ink, width: 1.3),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showPlanForm(context, plan: plan),
          child: AspectRatio(
            aspectRatio: 1.58, // proporción de tarjeta ID-1
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 34,
                  color: plan.active ? stripe : AppColors.borderStrong,
                  alignment: Alignment.center,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      plan.active ? 'MEMBRESÍA' : 'ARCHIVADO',
                      style: AppText.label.copyWith(
                        color: stripe == AppColors.plateYellow && plan.active ? AppColors.ink : AppColors.surface,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(plan.name.toUpperCase(), style: AppText.score(26), overflow: TextOverflow.ellipsis)),
                            // Perforación de llavero.
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.ink, width: 1.2),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(formatMoney(plan.priceCents), style: AppText.score(50)),
                        ),
                        Text('POR $days ${days == 1 ? 'DÍA' : 'DÍAS'}', style: AppText.label.copyWith(color: AppColors.ink)),
                        const Spacer(),
                        const Perforation(),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$activeMembers ${activeMembers == 1 ? 'cliente activo' : 'clientes activos'}',
                                style: AppText.mono(size: 11.5, color: AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(Icons.edit_outlined, size: 16, color: AppColors.textMuted),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showPlanForm(BuildContext context, {Plan? plan}) =>
    showDialog(context: context, builder: (_) => _PlanForm(plan: plan));

class _PlanForm extends ConsumerStatefulWidget {
  const _PlanForm({this.plan});

  final Plan? plan;

  @override
  ConsumerState<_PlanForm> createState() => _PlanFormState();
}

class _PlanFormState extends ConsumerState<_PlanForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.plan?.name);
  late final _price = TextEditingController(text: widget.plan == null ? '' : (widget.plan!.priceCents / 100).toStringAsFixed(2));
  late final _days = TextEditingController(text: '${widget.plan?.durationDays ?? 30}');
  late bool _active = widget.plan?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).savePlan(
            PlanInput(
              name: _name.text.trim(),
              priceCents: parseMoney(_price.text)!,
              durationDays: int.parse(_days.text),
              active: _active,
            ),
            id: widget.plan?.id,
          );
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Plan guardado');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo guardar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.plan != null;
    return FormDialog(
      title: editing ? 'Editar plan' : 'Nuevo plan',
      subtitle: editing ? 'Los pagos ya registrados conservan su precio original' : null,
      width: 460,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Guardar')),
      ],
      child: Form(
        key: _form,
        child: Column(
          spacing: 14,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre', hintText: 'Ej. Mensual'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Ingresa un nombre' : null,
            ),
            Row(
              spacing: 14,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Precio', prefixText: '$currencySymbol '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [MoneyInputFormatter()],
                    validator: (v) => parseMoney(v ?? '') == null ? 'Monto inválido' : null,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _days,
                    decoration: const InputDecoration(labelText: 'Duración', suffixText: 'días'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Mínimo 1 día' : null,
                  ),
                ),
              ],
            ),
            SwitchListTile(
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              contentPadding: EdgeInsets.zero,
              title: const Text('Disponible para cobrar'),
              subtitle: const Text('Archívalo para ocultarlo sin perder el historial', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    );
  }
}
