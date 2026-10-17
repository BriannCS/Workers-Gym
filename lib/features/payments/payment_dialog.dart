// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../data/rates.dart';
import '../../domain/models.dart';
import 'method_picker.dart';
import 'proof_widgets.dart';

Future<void> showPaymentDialog(BuildContext context, {Member? member}) => showDialog(
  context: context,
  builder: (_) => _PaymentDialog(initialMember: member),
);

class _PaymentDialog extends ConsumerStatefulWidget {
  const _PaymentDialog({this.initialMember});

  final Member? initialMember;

  @override
  ConsumerState<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends ConsumerState<_PaymentDialog> {
  late Member? _member = widget.initialMember;
  Plan? _plan;
  PaymentMethod? _method;
  bool _busy = false;
  final _proof = ProofDraft();

  @override
  void initState() {
    super.initState();
    // El botón Cobrar se habilita al escribir la referencia.
    _proof.addListener(_onProof);
  }

  void _onProof() => setState(() {});

  @override
  void dispose() {
    _proof
      ..removeListener(_onProof)
      ..dispose();
    super.dispose();
  }

  Future<void> _save(NewPayment payment) async {
    setState(() => _busy = true);
    try {
      final saved = await ref.read(gymRepositoryProvider).addPayment(payment);
      if (payment.method.requiresReference && mounted) {
        await uploadDraftReceipt(context, ref, _proof, ProofKind.payment, saved.id);
      }
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      final amount = saved.amountVesCents == null ? formatMoney(saved.amountCents) : formatVes(saved.amountVesCents!);
      showToast(context, 'Pago de $amount (${saved.methodName}) registrado · activo hasta ${formatDate(saved.periodEnd)}');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo registrar el pago: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider)();
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final plans = (ref.watch(plansProvider).value ?? const <Plan>[]).where((p) => p.active).toList();
    final plan = _plan ?? plans.where((p) => p.durationDays == 30).firstOrNull ?? plans.firstOrNull;
    final member = _member;
    final method = _method ?? activeMethods(ref).firstOrNull;
    final rate = ref.watch(currentRateProvider).value;
    final payment = member == null || plan == null || method == null
        ? null
        : NewPayment.renewal(member: member, plan: plan, method: method, today: today, rate: rate, proof: _proof.input);

    return FormDialog(
      title: 'Registrar pago',
      subtitle: 'Membresía: el periodo se calcula desde el último vencimiento',
      width: 600,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: payment == null || !payment.ready || _busy ? null : () => _save(payment),
          child: Text(payment == null ? 'Cobrar' : chargeLabel(payment.amountCents, method, rate)),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Label('Cliente'),
          LayoutBuilder(
            builder: (context, c) => DropdownMenu<Member>(
              width: c.maxWidth,
              initialSelection: member,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 320,
              hintText: 'Busca por nombre o cédula',
              leadingIcon: const Icon(Icons.search, size: 20),
              onSelected: (m) => setState(() => _member = m),
              dropdownMenuEntries: [
                for (final m in members)
                  DropdownMenuEntry(
                    value: m,
                    label: m.documentId == null ? m.fullName : '${m.fullName} · ${formatDocument(m.documentId)}',
                    trailingIcon: StatusBadge(m.status(today)),
                  ),
              ],
            ),
          ),
          if (member != null) ...[
            const SizedBox(height: 8),
            Text(
              member.expiresOn == null
                  ? 'Sin pagos previos: el periodo empieza hoy.'
                  : '${member.status(today).label} · vence el ${formatDate(member.expiresOn!)} (${relativeDays(daysLeft(member.expiresOn!, today))})',
              style: TextStyle(color: AppColors.forStatus(member.status(today)), fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          const _Label('Plan'),
          if (plans.isEmpty)
            const Text('No hay planes activos. Crea uno en la sección Planes.', style: TextStyle(color: AppColors.warning))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final p in plans) _PlanOption(plan: p, selected: p.id == plan?.id, onTap: () => setState(() => _plan = p))],
            ),
          const SizedBox(height: 20),
          const _Label('Método de pago'),
          MethodPicker(selected: method, onChanged: (m) => setState(() => _method = m)),
          if (method != null) ProofFields(draft: _proof, method: method),
          if (payment != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              color: AppColors.bg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Perforation(),
                  const SizedBox(height: 10),
                  Text('NUEVO PERIODO', style: AppText.label),
                  LeaderLine('Desde', formatDate(payment.periodStart)),
                  LeaderLine('Hasta', formatDate(payment.periodEnd), strong: true),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('A COBRAR', style: AppText.label.copyWith(color: AppColors.ink)),
                      const Spacer(),
                      Text(formatMoney(payment.amountCents), style: AppText.score(40)),
                    ],
                  ),
                  BolivarCharge(usdCents: payment.amountCents, method: method),
                  const SizedBox(height: 10),
                  const Perforation(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text.toUpperCase(), style: AppText.label),
  );
}

class _PlanOption extends StatelessWidget {
  const _PlanOption({required this.plan, required this.selected, required this.onTap});

  final Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.surface : AppColors.ink;
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        side: const BorderSide(color: AppColors.ink, width: 1.3),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 122,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.name.toUpperCase(),
                  style: AppText.label.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(formatMoney(plan.priceCents), style: AppText.score(26, color: fg)),
                Text(
                  '${plan.durationDays} ${plan.durationDays == 1 ? 'día' : 'días'}',
                  style: AppText.mono(size: 11.5, color: selected ? AppColors.plateYellow : AppColors.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
