// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';

/// Compras a proveedores: es lo que alimenta el inventario.
/// Stock actual = stock inicial ± ajustes + compras − ventas.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(clockProvider)();
    final purchases = ref.watch(purchasesProvider);
    final month = (purchases.value ?? const <Purchase>[])
        .where((p) => !p.voided && p.purchasedOn.year == today.year && p.purchasedOn.month == today.month)
        .toList();

    return PageBody(
      header: PageHeader(
        title: 'Compras',
        subtitle: 'Mercancía que entra al inventario',
        actions: [
          if (ref.watch(canProvider(Perm.inventoryManage)))
            FilledButton.icon(
              onPressed: () => showPurchaseForm(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva compra'),
            ),
        ],
      ),
      children: [
        ScoreBoard(scores: [
          Score(label: 'Comprado este mes', value: formatMoney(month.fold(0, (s, p) => s + p.totalCents)), color: AppColors.info),
          Score(label: 'Facturas del mes', value: '${month.length}'),
          Score(label: 'Unidades recibidas', value: '${month.fold(0, (s, p) => s + p.units)}', color: AppColors.success),
        ]),
        const SizedBox(height: 28),
        Panel(
          title: 'Facturas',
          padding: EdgeInsets.zero,
          child: AsyncView(
            purchases,
            onRetry: () => ref.invalidate(purchasesProvider),
            data: (list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: 'Sin compras registradas',
                    message: 'Cada compra suma al stock de sus productos.',
                    action: ref.watch(canProvider(Perm.inventoryManage))
                        ? FilledButton(onPressed: () => showPurchaseForm(context), child: const Text('Nueva compra'))
                        : null,
                  )
                : LayoutBuilder(
                    builder: (context, c) => Column(
                      children: [
                        if (c.maxWidth >= 760)
                          const TableHeader(cells: [('Fecha', 2), ('Proveedor', 4), ('Factura', 2), ('Productos', 5), ('Total', 2)]),
                        for (final p in list) _PurchaseRow(purchase: p, compact: c.maxWidth < 760),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase, required this.compact});

  final Purchase purchase;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final strike = p.voided ? TextDecoration.lineThrough : null;
    final muted = AppText.mono(size: 12.5, color: AppColors.textMuted).copyWith(decoration: strike);
    final items = p.items.map((i) => '${i.quantity}× ${i.productName}').join(', ');
    final total = Text(formatMoney(p.totalCents), textAlign: TextAlign.right, style: AppText.mono(size: 13.5, weight: FontWeight.w600).copyWith(decoration: strike));
    return Opacity(
      opacity: p.voided ? .5 : 1,
      child: InkWell(
        onTap: () => showDialog<void>(context: context, builder: (_) => _PurchaseDetail(purchase: p)),
        hoverColor: AppColors.raised,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: const BoxDecoration(border: rowRule),
          child: compact
              ? Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.supplierName ?? 'Sin proveedor', style: TextStyle(fontWeight: FontWeight.w600, decoration: strike)),
                          Text([formatShortDate(p.purchasedOn), ?p.invoice].join(' · '), style: muted),
                          Text(p.voided ? 'ANULADA: ${p.voidReason}' : items, style: muted.copyWith(color: p.voided ? AppColors.danger : null), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    total,
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 2, child: Text(formatShortDate(p.purchasedOn), style: muted)),
                    Expanded(
                      flex: 4,
                      child: Text(p.supplierName ?? 'Sin proveedor', style: TextStyle(fontWeight: FontWeight.w600, decoration: strike), overflow: TextOverflow.ellipsis),
                    ),
                    Expanded(flex: 2, child: Text(p.invoice ?? '—', style: muted)),
                    Expanded(
                      flex: 5,
                      child: Text(
                        p.voided ? 'ANULADA: ${p.voidReason}' : items,
                        style: muted.copyWith(color: p.voided ? AppColors.danger : null),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(flex: 2, child: total),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PurchaseDetail extends ConsumerWidget {
  const _PurchaseDetail({required this.purchase});

  final Purchase purchase;

  Future<void> _void(BuildContext context, WidgetRef ref) async {
    final reason = await askVoidReason(
      context,
      title: 'Anular compra',
      detail: '${purchase.supplierName ?? 'Sin proveedor'} · ${formatMoney(purchase.totalCents)}. Se retira del stock lo que entró.',
    );
    if (reason == null) return;
    try {
      await ref.read(gymRepositoryProvider).voidPurchase(purchase.id, reason);
      refreshGymData(ref);
      if (!context.mounted) return;
      Navigator.pop(context);
      showToast(context, 'Compra anulada, stock corregido');
    } catch (e) {
      if (context.mounted) showToast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = purchase;
    return FormDialog(
      title: 'Compra',
      subtitle: [p.supplierName ?? 'Sin proveedor', formatDate(p.purchasedOn), if (p.invoice != null) 'factura ${p.invoice}'].join(' · '),
      width: 520,
      actions: [
        if (!p.voided && ref.watch(canProvider(Perm.inventoryManage)))
          OutlinedButton.icon(
            onPressed: () => _void(context, ref),
            icon: const Icon(Icons.block, size: 18),
            label: const Text('Anular'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (p.voided)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: AppColors.danger, width: 1.5)),
              child: Text('ANULADA · ${p.voidReason}', style: AppText.mono(size: 12.5, weight: FontWeight.w600, color: AppColors.danger)),
            ),
          Text('PRODUCTOS', style: AppText.label),
          for (final i in p.items) LeaderLine('${i.quantity} × ${i.productName} @ ${formatMoney(i.unitCostCents)}', formatMoney(i.totalCents)),
          const SizedBox(height: 10),
          const Perforation(),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink)),
              const Spacer(),
              Text(formatMoney(p.totalCents), style: AppText.score(36)),
            ],
          ),
          if (p.notes != null) ...[
            const SizedBox(height: 10),
            Text(p.notes!, style: AppText.muted),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nueva compra

Future<void> showPurchaseForm(BuildContext context) => showDialog(context: context, builder: (_) => const _PurchaseForm());

class _Line {
  _Line();

  Product? product;
  final qty = TextEditingController(text: '1');
  final cost = TextEditingController();

  int get quantity => int.tryParse(qty.text) ?? 0;
  int? get unitCostCents => parseMoney(cost.text);
  int get totalCents => quantity * (unitCostCents ?? 0);

  void dispose() {
    qty.dispose();
    cost.dispose();
  }
}

class _PurchaseForm extends ConsumerStatefulWidget {
  const _PurchaseForm();

  @override
  ConsumerState<_PurchaseForm> createState() => _PurchaseFormState();
}

class _PurchaseFormState extends ConsumerState<_PurchaseForm> {
  final _form = GlobalKey<FormState>();
  final _invoice = TextEditingController();
  final _notes = TextEditingController();
  final _lines = [_Line()];
  String? _supplierId;
  DateTime? _date;
  bool _busy = false;

  @override
  void dispose() {
    _invoice.dispose();
    _notes.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save(DateTime date) async {
    if (!_form.currentState!.validate()) return;
    if (_lines.any((l) => l.product == null)) {
      showToast(context, 'Elige el producto de cada línea', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).registerPurchase(NewPurchase(
            supplierId: _supplierId,
            invoice: _invoice.text.trim().isEmpty ? null : _invoice.text.trim(),
            purchasedOn: date,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            lines: [
              for (final l in _lines) PurchaseLine(product: l.product!, quantity: l.quantity, unitCostCents: l.unitCostCents!),
            ],
          ));
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Compra registrada · ${_lines.fold(0, (s, l) => s + l.quantity)} unidades al inventario');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo registrar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(clockProvider)();
    final date = _date ?? DateTime(today.year, today.month, today.day);
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];
    final products = (ref.watch(productsProvider).value ?? const <Product>[]).where((p) => p.active).toList();
    final total = _lines.fold(0, (s, l) => s + l.totalCents);

    return FormDialog(
      title: 'Nueva compra',
      subtitle: 'Suma al stock y actualiza el costo de cada producto',
      width: 720,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : () => _save(date), child: Text('Registrar ${formatMoney(total)}')),
      ],
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _supplierId,
                    decoration: const InputDecoration(labelText: 'Proveedor'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Sin proveedor')),
                      for (final s in suppliers) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: TextFormField(controller: _invoice, decoration: const InputDecoration(labelText: 'N.º de factura')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: today);
                    if (picked != null) setState(() => _date = picked);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 18),
                  label: Text(formatDate(date)),
                ),
              ],
            ),
            Text('PRODUCTOS', style: AppText.label),
            for (final (i, line) in _lines.indexed)
              _LineEditor(
                key: ObjectKey(line),
                line: line,
                products: products,
                onChanged: () => setState(() {}),
                onRemove: _lines.length == 1
                    ? null
                    : () => setState(() {
                          _lines.removeAt(i).dispose();
                        }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _lines.add(_Line())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Agregar producto'),
              ),
            ),
            TextFormField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas'), maxLines: 2),
            const Perforation(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink)),
                const Spacer(),
                Text(formatMoney(total), style: AppText.score(36)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({super.key, required this.line, required this.products, required this.onChanged, required this.onRemove});

  final _Line line;
  final List<Product> products;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final productField = LayoutBuilder(
      builder: (context, c) => DropdownMenu<Product>(
        width: c.maxWidth,
        initialSelection: line.product,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 300,
        hintText: 'Producto',
        onSelected: (p) {
          line.product = p;
          // Propone el último costo conocido.
          if (p != null && line.cost.text.isEmpty) line.cost.text = (p.costCents / 100).toStringAsFixed(2);
          onChanged();
        },
        dropdownMenuEntries: [for (final p in products) DropdownMenuEntry(value: p, label: p.name)],
      ),
    );
    final qty = SizedBox(
      width: 90,
      child: TextFormField(
        controller: line.qty,
        decoration: const InputDecoration(labelText: 'Cant.'),
        keyboardType: TextInputType.number,
        inputFormatters: digitsOnly,
        onChanged: (_) => onChanged(),
        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? '> 0' : null,
      ),
    );
    final cost = SizedBox(
      width: 120,
      child: TextFormField(
        controller: line.cost,
        decoration: const InputDecoration(labelText: 'Costo c/u', prefixText: '$currencySymbol '),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: const [MoneyInputFormatter()],
        onChanged: (_) => onChanged(),
        validator: (v) => parseMoney(v ?? '') == null ? 'Monto' : null,
      ),
    );
    final subtotal = SizedBox(
      width: 90,
      child: Text(formatMoney(line.totalCents), textAlign: TextAlign.right, style: AppText.mono(size: 13, weight: FontWeight.w600)),
    );
    final remove = IconButton(tooltip: 'Quitar línea', onPressed: onRemove, icon: const Icon(Icons.close, size: 18));

    if (context.isPhone) {
      return Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(border: rowRule),
        child: Column(
          spacing: 8,
          children: [
            Row(children: [Expanded(child: productField), remove]),
            Row(spacing: 10, children: [qty, Expanded(child: cost), subtotal]),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [Expanded(child: productField), qty, cost, Padding(padding: const EdgeInsets.only(top: 16), child: subtotal), remove],
    );
  }
}
