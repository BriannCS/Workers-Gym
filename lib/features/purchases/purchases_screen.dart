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
import '../../core/widgets/barcode_scanner.dart';
import '../../data/rates.dart';
import '../payments/method_picker.dart';

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
        ScoreBoard(
          scores: [
            Score(label: 'Comprado este mes', value: formatMoney(month.fold(0, (s, p) => s + p.totalCents)), color: AppColors.info),
            Score(
              label: 'Pagado en dólares',
              value: formatMoney(month.where((p) => p.currency == Currency.usd).fold(0, (s, p) => s + p.totalCents)),
              caption: '${month.where((p) => p.currency == Currency.usd).length} facturas',
            ),
            Score(
              label: 'Pagado en bolívares',
              value: formatVes(month.fold(0, (s, p) => s + (p.totalVesCents ?? 0))),
              caption: '${month.where((p) => p.currency == Currency.ves).length} facturas',
              color: AppColors.plateBlue,
            ),
            Score(label: 'Unidades recibidas', value: '${month.fold(0, (s, p) => s + p.units)}', color: AppColors.success),
          ],
        ),
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
                          const TableHeader(
                            cells: [('Fecha', 2), ('Proveedor', 4), ('Factura', 2), ('Productos', 5), ('Pago', 3), ('Total', 2)],
                          ),
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
    final total = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatMoney(p.totalCents),
          textAlign: TextAlign.right,
          style: AppText.mono(size: 13.5, weight: FontWeight.w600).copyWith(decoration: strike),
        ),
        if (p.totalVesCents != null)
          Text(
            formatVes(p.totalVesCents!),
            textAlign: TextAlign.right,
            style: muted.copyWith(fontSize: 11, color: AppColors.plateBlue),
          ),
      ],
    );
    final paidWith = p.methodName ?? 'Sin indicar';
    return Opacity(
      opacity: p.voided ? .5 : 1,
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _PurchaseDetail(purchase: p),
        ),
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
                          Text(
                            p.supplierName ?? 'Sin proveedor',
                            style: TextStyle(fontWeight: FontWeight.w600, decoration: strike),
                          ),
                          Text([formatShortDate(p.purchasedOn), ?p.invoice, paidWith].join(' · '), style: muted),
                          Text(
                            p.voided ? 'ANULADA: ${p.voidReason}' : items,
                            style: muted.copyWith(color: p.voided ? AppColors.danger : null),
                            overflow: TextOverflow.ellipsis,
                          ),
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
                      child: Text(
                        p.supplierName ?? 'Sin proveedor',
                        style: TextStyle(fontWeight: FontWeight.w600, decoration: strike),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(flex: 2, child: Text(p.invoice ?? '—', style: muted)),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          p.voided ? 'ANULADA: ${p.voidReason}' : items,
                          style: muted.copyWith(color: p.voided ? AppColors.danger : null),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        paidWith,
                        style: muted.copyWith(color: p.methodName == null ? AppColors.textMuted.withValues(alpha: .6) : null),
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
          OutlinedButton.icon(onPressed: () => _void(context, ref), icon: const Icon(Icons.block, size: 18), label: const Text('Anular')),
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
              child: Text(
                'ANULADA · ${p.voidReason}',
                style: AppText.mono(size: 12.5, weight: FontWeight.w600, color: AppColors.danger),
              ),
            ),
          Text('PRODUCTOS', style: AppText.label),
          for (final i in p.items)
            LeaderLine('${i.quantity} × ${i.productName} @ ${formatMoney(i.unitCostCents)}', formatMoney(i.totalCents)),
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
          const SizedBox(height: 10),
          Text('PAGO AL PROVEEDOR', style: AppText.label),
          LeaderLine('Método', p.methodName ?? 'Sin indicar'),
          if (p.totalVesCents != null) ...[
            LeaderLine('Tasa ${p.rateSource?.label ?? ''}', 'Bs. ${formatRate(p.rate ?? 0)}', color: AppColors.textMuted),
            LeaderLine('Pagado en bolívares', formatVes(p.totalVesCents!), strong: true, color: AppColors.plateBlue),
          ],
          if (p.paymentReference != null) LeaderLine('Referencia', p.paymentReference!),
          if (p.notes != null) ...[const SizedBox(height: 10), Text(p.notes!, style: AppText.muted)],
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
  final _payRef = TextEditingController();
  final _lines = [_Line()];
  String? _supplierId;
  PaymentMethod? _method;
  DateTime? _date;
  bool _busy = false;

  @override
  void dispose() {
    _invoice.dispose();
    _notes.dispose();
    _payRef.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  /// Crea un producto sin salir de la compra y lo pone en la línea.
  Future<void> _newProduct(_Line line, {String? sku}) async {
    final created = await showQuickProductDialog(context, sku: sku, supplierId: _supplierId, costCents: line.unitCostCents);
    if (created == null || !mounted) return;
    setState(() {
      line.product = created;
      if (line.cost.text.isEmpty && created.costCents != null) line.cost.text = (created.costCents! / 100).toStringAsFixed(2);
    });
  }

  /// Escanea el código: si el producto existe lo pone en la línea; si no,
  /// ofrece crearlo con ese código.
  Future<void> _scan(_Line line) async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final products = ref.read(productsProvider).value ?? const <Product>[];
    final p = products.where((p) => p.sku?.toLowerCase() == code.toLowerCase()).firstOrNull;
    if (p != null) {
      setState(() {
        line.product = p;
        final known = p.costCents;
        if (known != null && line.cost.text.isEmpty) line.cost.text = (known / 100).toStringAsFixed(2);
      });
      showToast(context, '${p.name}${p.active ? '' : ' (archivado)'}');
      return;
    }
    await _newProduct(line, sku: code);
  }

  Future<void> _save(DateTime date, PaymentMethod? method, ExchangeRate? rate) async {
    if (!_form.currentState!.validate()) return;
    if (_lines.any((l) => l.product == null)) {
      showToast(context, 'Elige el producto de cada línea', error: true);
      return;
    }
    if (method == null) {
      showToast(context, 'Indica con qué se le pagó al proveedor', error: true);
      return;
    }
    if (method.inBolivares && rate == null) {
      showToast(context, 'No hay tasa del día para registrar el pago en bolívares. Revisa Ajustes.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(gymRepositoryProvider)
          .registerPurchase(
            NewPurchase(
              supplierId: _supplierId,
              invoice: _invoice.text.trim().isEmpty ? null : _invoice.text.trim(),
              purchasedOn: date,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
              lines: [for (final l in _lines) PurchaseLine(product: l.product!, quantity: l.quantity, unitCostCents: l.unitCostCents!)],
              method: method,
              rate: method.inBolivares ? rate : null,
              paymentReference: _payRef.text.trim().isEmpty ? null : _payRef.text.trim(),
            ),
          );
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
    final method = _method;
    final rate = ref.watch(currentRateProvider).value;
    final inBs = method != null && method.inBolivares && rate != null;

    return FormDialog(
      title: 'Nueva compra',
      subtitle: 'Suma al stock y actualiza el costo de cada producto',
      width: 720,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : () => _save(date, method, rate),
          child: Text('Registrar ${inBs ? formatVes(rate.vesCents(total)) : formatMoney(total)}'),
        ),
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
                      for (final s in suppliers)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(s.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _supplierId = v),
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: TextFormField(
                    controller: _invoice,
                    decoration: const InputDecoration(labelText: 'N.º de factura'),
                  ),
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
                onNewProduct: () => _newProduct(line),
                onScan: canScanBarcodes ? () => _scan(line) : null,
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
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              maxLines: 2,
            ),
            const Perforation(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink)),
                const Spacer(),
                Text(formatMoney(total), style: AppText.score(36)),
              ],
            ),
            Text('¿CON QUÉ SE LE PAGÓ AL PROVEEDOR? *', style: AppText.label),
            MethodPicker(selected: method, onChanged: (m) => setState(() => _method = m)),
            if (method != null) BolivarCharge(usdCents: total, method: method),
            if (method != null && method.requiresReference)
              TextFormField(
                controller: _payRef,
                decoration: const InputDecoration(labelText: 'Referencia del pago (opcional)'),
              ),
          ],
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.products,
    required this.onChanged,
    required this.onRemove,
    required this.onNewProduct,
    required this.onScan,
  });

  final _Line line;
  final List<Product> products;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final VoidCallback onNewProduct;
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final picker = LayoutBuilder(
      builder: (context, c) => DropdownMenu<Product>(
        // Cambia al crear o escanear un producto: así se ve seleccionado.
        key: ValueKey(line.product?.id),
        width: c.maxWidth,
        initialSelection: line.product,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 300,
        hintText: 'Producto',
        onSelected: (p) {
          line.product = p;
          // Propone el último costo conocido.
          final known = p?.costCents;
          if (known != null && line.cost.text.isEmpty) line.cost.text = (known / 100).toStringAsFixed(2);
          onChanged();
        },
        dropdownMenuEntries: [
          for (final p in [...products.where((p) => p.id != line.product?.id), ?line.product])
            DropdownMenuEntry(value: p, label: p.sku == null ? p.name : '${p.name} · ${p.sku}'),
        ],
      ),
    );
    final productField = Row(
      children: [
        Expanded(child: picker),
        if (onScan != null) IconButton(tooltip: 'Escanear código', onPressed: onScan, icon: const Icon(Icons.qr_code_scanner)),
        IconButton(tooltip: 'Crear producto nuevo', onPressed: onNewProduct, icon: const Icon(Icons.add_box_outlined)),
      ],
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
      child: Text(
        formatMoney(line.totalCents),
        textAlign: TextAlign.right,
        style: AppText.mono(size: 13, weight: FontWeight.w600),
      ),
    );
    final remove = IconButton(tooltip: 'Quitar línea', onPressed: onRemove, icon: const Icon(Icons.close, size: 18));

    if (context.isPhone) {
      return Container(
        padding: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(border: rowRule),
        child: Column(
          spacing: 8,
          children: [
            Row(
              children: [
                Expanded(child: productField),
                remove,
              ],
            ),
            Row(
              spacing: 10,
              children: [
                qty,
                Expanded(child: cost),
                subtotal,
              ],
            ),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Expanded(child: productField),
        qty,
        cost,
        Padding(padding: const EdgeInsets.only(top: 16), child: subtotal),
        remove,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Producto nuevo desde la compra

/// Alta rápida de un producto (nombre, código, precio y mínimo). El costo y el
/// proveedor salen de la compra; el stock entra con la propia compra.
Future<Product?> showQuickProductDialog(BuildContext context, {String? sku, String? supplierId, int? costCents}) => showDialog<Product>(
  context: context,
  builder: (_) => _QuickProduct(sku: sku, supplierId: supplierId, costCents: costCents),
);

class _QuickProduct extends ConsumerStatefulWidget {
  const _QuickProduct({this.sku, this.supplierId, this.costCents});

  final String? sku;
  final String? supplierId;
  final int? costCents;

  @override
  ConsumerState<_QuickProduct> createState() => _QuickProductState();
}

class _QuickProductState extends ConsumerState<_QuickProduct> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  late final _sku = TextEditingController(text: widget.sku);
  final _price = TextEditingController();
  final _min = TextEditingController(text: '0');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _sku, _price, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final sku = _sku.text.trim().isEmpty ? null : _sku.text.trim();
    final products = ref.read(productsProvider).value ?? const <Product>[];
    final clash = products.where((p) => sku != null && p.sku?.toLowerCase() == sku.toLowerCase()).firstOrNull;
    if (clash != null) {
      showToast(context, 'El código $sku ya es de "${clash.name}". Elige ese producto en la lista.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final input = ProductInput(
        name: _name.text.trim(),
        sku: sku,
        priceCents: parseMoney(_price.text)!,
        costCents: widget.costCents ?? 0,
        minStock: int.tryParse(_min.text) ?? 0,
        supplierId: widget.supplierId,
      );
      final id = await ref.read(gymRepositoryProvider).saveProduct(input);
      ref.invalidate(productsProvider);
      if (!mounted) return;
      showToast(context, 'Producto "${input.name}" creado');
      Navigator.pop(
        context,
        Product(
          id: id,
          name: input.name,
          sku: input.sku,
          priceCents: input.priceCents,
          costCents: input.costCents,
          stock: 0,
          minStock: input.minStock,
          supplierId: input.supplierId,
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo crear: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String? money(String? v) => parseMoney(v ?? '') == null ? 'Monto inválido' : null;
    return FormDialog(
      title: 'Producto nuevo',
      subtitle: 'El costo y el stock salen de esta compra',
      width: 480,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Crear y usar')),
      ],
      child: Form(
        key: _form,
        child: Column(
          spacing: 14,
          children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Ingresa un nombre' : null,
            ),
            TextFormField(
              controller: _sku,
              decoration: InputDecoration(
                labelText: 'Código (SKU)',
                suffixIcon: ScanButton(onScanned: (code) => setState(() => _sku.text = code)),
              ),
            ),
            Row(
              spacing: 14,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Precio de venta *', prefixText: '$currencySymbol '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: const [MoneyInputFormatter()],
                    validator: money,
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    decoration: const InputDecoration(labelText: 'Stock mínimo'),
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
