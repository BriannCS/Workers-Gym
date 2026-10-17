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

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  bool _suppliersTab = false;
  bool _onlyLow = false;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final active = (products.value ?? const <Product>[]).where((p) => p.active);
    final lowCount = active.where((p) => p.lowStock).length;
    // Recepción solo ve el stock: sin costos, márgenes ni proveedores.
    final showCost = ref.watch(canProvider(Perm.inventoryCost));
    final showSuppliers = ref.watch(canProvider(Perm.purchasesView)) || ref.watch(canProvider(Perm.inventoryManage));
    final suppliersTab = _suppliersTab && showSuppliers;
    final value = active.fold(0, (s, p) => s + p.stock * (p.costCents ?? 0));

    return PageBody(
      header: PageHeader(
        title: 'Inventario',
        subtitle: showSuppliers ? 'Productos de la tienda y proveedores' : 'Stock actual de la tienda',
        actions: [
          if (!ref.watch(canProvider(Perm.inventoryManage)))
            const SizedBox.shrink()
          else if (suppliersTab)
            FilledButton.icon(
              onPressed: () => _showSupplierForm(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo proveedor'),
            )
          else
            FilledButton.icon(
              onPressed: () => _showProductForm(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nuevo producto'),
            ),
        ],
      ),
      children: [
        ScoreBoard(
          scores: [
            Score(label: 'Productos activos', value: '${active.length}'),
            Score(
              label: 'Stock bajo',
              value: '$lowCount',
              color: lowCount == 0 ? AppColors.success : AppColors.warning,
              caption: 'en o por debajo del mínimo',
              onTap: () => setState(() {
                _suppliersTab = false;
                _onlyLow = true;
              }),
            ),
            if (showCost)
              Score(label: 'Valor del inventario', value: formatMoney(value), color: AppColors.info, caption: 'a precio de costo')
            else
              Score(
                label: 'Agotados',
                value: '${active.where((p) => p.stock == 0).length}',
                color: active.any((p) => p.stock == 0) ? AppColors.danger : AppColors.success,
                caption: 'sin unidades',
              ),
          ],
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (showSuppliers)
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Productos'), icon: Icon(Icons.inventory_2_outlined)),
                  ButtonSegment(value: true, label: Text('Proveedores'), icon: Icon(Icons.local_shipping_outlined)),
                ],
                selected: {suppliersTab},
                onSelectionChanged: (s) => setState(() => _suppliersTab = s.first),
                showSelectedIcon: false,
              ),
            if (!suppliersTab)
              FilterChip(label: Text('Solo stock bajo  $lowCount'), selected: _onlyLow, onSelected: (v) => setState(() => _onlyLow = v)),
          ],
        ),
        const SizedBox(height: 16),
        Panel(
          padding: EdgeInsets.zero,
          child: suppliersTab
              ? const _SuppliersTable()
              : _ProductsTable(onlyLow: _onlyLow, showCost: showCost, showSupplier: showSuppliers),
        ),
      ],
    );
  }
}

class _ProductsTable extends ConsumerWidget {
  const _ProductsTable({required this.onlyLow, required this.showCost, required this.showSupplier});

  final bool onlyLow;
  final bool showCost;
  final bool showSupplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      ref.watch(productsProvider),
      onRetry: () => ref.invalidate(productsProvider),
      data: (list) {
        final visible = list.where((p) => !onlyLow || (p.active && p.lowStock)).toList();
        if (visible.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2_outlined,
            title: list.isEmpty ? 'Sin productos' : 'Nada con stock bajo',
            action: list.isEmpty && ref.watch(canProvider(Perm.inventoryManage))
                ? FilledButton(onPressed: () => _showProductForm(context), child: const Text('Nuevo producto'))
                : null,
          );
        }
        return LayoutBuilder(
          builder: (context, c) => Column(
            children: [
              if (c.maxWidth >= 760)
                TableHeader(
                  cells: [
                    ('Producto', 5),
                    if (showSupplier) ('Proveedor', 3),
                    ('Precio', 2),
                    if (showCost) ...[('Costo', 2), ('Margen', 2)],
                    ('Stock', 3),
                    ('', 2),
                  ],
                ),
              for (final p in visible)
                _ProductRow(
                  product: p,
                  compact: c.maxWidth < 760,
                  canManage: ref.watch(canProvider(Perm.inventoryManage)),
                  showCost: showCost,
                  showSupplier: showSupplier,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.product,
    required this.compact,
    required this.canManage,
    required this.showCost,
    required this.showSupplier,
  });

  final Product product;
  final bool compact;
  final bool canManage;
  final bool showCost;
  final bool showSupplier;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final muted = AppText.mono(size: 12.5, color: AppColors.textMuted);
    final cost = showCost ? p.costCents : null;
    final margin = p.priceCents == 0 || cost == null ? null : (p.priceCents - cost) / p.priceCents * 100;
    final stockColor = p.stock == 0 ? AppColors.danger : (p.lowStock ? AppColors.warning : AppColors.success);
    final stock = Text('${p.stock}', style: AppText.score(26, color: stockColor));
    final actions = [
      if (canManage)
        IconButton(
          tooltip: 'Ajuste de inventario',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => _StockDialog(product: p),
          ),
          icon: const Icon(Icons.tune, size: 20),
        ),
      if (canManage)
        IconButton(
          tooltip: 'Editar',
          onPressed: () => _showProductForm(context, product: p),
          icon: const Icon(Icons.edit_outlined, size: 20),
        ),
    ];
    final name = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        Text([?p.sku, if (!p.active) 'ARCHIVADO'].join(' · '), style: muted.copyWith(fontSize: 11.5)),
      ],
    );

    final Widget row;
    if (compact) {
      row = Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  const SizedBox(height: 4),
                  Text(
                    [
                      formatMoney(p.priceCents),
                      if (cost != null) 'costo ${formatMoney(cost)}',
                      if (showSupplier) p.supplierName ?? 'sin proveedor',
                    ].join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
            stock,
            ...actions,
          ],
        ),
      );
    } else {
      row = Container(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        constraints: const BoxConstraints(minHeight: 60),
        decoration: const BoxDecoration(border: rowRule),
        child: Row(
          children: [
            Expanded(flex: 5, child: name),
            if (showSupplier)
              Expanded(
                flex: 3,
                child: Text(p.supplierName ?? '—', style: muted, overflow: TextOverflow.ellipsis),
              ),
            Expanded(
              flex: 2,
              child: Text(formatMoney(p.priceCents), style: AppText.mono(size: 13.5, weight: FontWeight.w600)),
            ),
            if (showCost) ...[
              Expanded(flex: 2, child: Text(cost == null ? '—' : formatMoney(cost), style: muted)),
              Expanded(flex: 2, child: Text(margin == null ? '—' : '${margin.toStringAsFixed(0)}%', style: muted)),
            ],
            Expanded(
              flex: 3,
              child: Align(alignment: Alignment.centerLeft, child: stock),
            ),
            Expanded(
              flex: 2,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ),
          ],
        ),
      );
    }
    return Opacity(opacity: p.active ? 1 : .5, child: row);
  }
}

class _SuppliersTable extends ConsumerWidget {
  const _SuppliersTable();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final muted = AppText.mono(size: 12.5, color: AppColors.textMuted);
    return AsyncView(
      ref.watch(suppliersProvider),
      onRetry: () => ref.invalidate(suppliersProvider),
      data: (list) => list.isEmpty
          ? EmptyState(
              icon: Icons.local_shipping_outlined,
              title: 'Sin proveedores',
              action: FilledButton(onPressed: () => _showSupplierForm(context), child: const Text('Nuevo proveedor')),
            )
          : LayoutBuilder(
              builder: (context, c) => Column(
                children: [
                  if (c.maxWidth >= 760)
                    const TableHeader(cells: [('Proveedor', 4), ('Teléfono', 3), ('Correo', 4), ('Productos', 2), ('', 1)]),
                  for (final s in list)
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
                      decoration: const BoxDecoration(border: rowRule),
                      child: c.maxWidth < 760
                          ? Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      Text(
                                        [
                                          if (s.phone != null) formatPhone(s.phone),
                                          ?s.email,
                                          '${products.where((p) => p.supplierId == s.id).length} productos',
                                        ].join(' · '),
                                        style: muted,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Editar',
                                  onPressed: ref.watch(canProvider(Perm.inventoryManage))
                                      ? () => _showSupplierForm(context, supplier: s)
                                      : null,
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                Expanded(flex: 3, child: Text(formatPhone(s.phone), style: muted)),
                                Expanded(
                                  flex: 4,
                                  child: Text(s.email ?? '—', style: muted, overflow: TextOverflow.ellipsis),
                                ),
                                Expanded(flex: 2, child: Text('${products.where((p) => p.supplierId == s.id).length}', style: muted)),
                                Expanded(
                                  flex: 1,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      tooltip: 'Editar',
                                      onPressed: ref.watch(canProvider(Perm.inventoryManage))
                                          ? () => _showSupplierForm(context, supplier: s)
                                          : null,
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Formularios

String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

Future<void> _showProductForm(BuildContext context, {Product? product}) => showDialog(
  context: context,
  builder: (_) => _ProductForm(product: product),
);

class _ProductForm extends ConsumerStatefulWidget {
  const _ProductForm({this.product});

  final Product? product;

  @override
  ConsumerState<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends ConsumerState<_ProductForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name);
  late final _sku = TextEditingController(text: widget.product?.sku);
  late final _price = TextEditingController(text: _cents(widget.product?.priceCents));
  late final _cost = TextEditingController(text: _cents(widget.product?.costCents));
  late final _min = TextEditingController(text: '${widget.product?.minStock ?? 0}');
  final _initial = TextEditingController(text: '0');
  late String? _supplierId = widget.product?.supplierId;
  late bool _active = widget.product?.active ?? true;
  bool _busy = false;

  static String _cents(int? c) => c == null ? '' : (c / 100).toStringAsFixed(2);

  /// Código leído con la cámara. Si ya es de otro producto, avisa y ofrece
  /// abrir ese en vez de crear uno repetido.
  Future<void> _onScanned(String code) async {
    final products = ref.read(productsProvider).value ?? const <Product>[];
    final clash = products.where((p) => p.id != widget.product?.id && p.sku?.toLowerCase() == code.toLowerCase()).firstOrNull;
    if (clash == null) {
      setState(() => _sku.text = code);
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ese código ya existe'),
        content: Text('El código $code es de "${clash.name}" (stock ${clash.stock}). ¿Abrir ese producto?'),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Abrir producto')),
        ],
      ),
    );
    if (open != true || !mounted) return;
    // Este formulario se cierra: el nuevo se abre desde la pantalla de abajo.
    final navigator = Navigator.of(context);
    navigator.pop();
    _showProductForm(navigator.context, product: clash);
  }

  @override
  void dispose() {
    for (final c in [_name, _sku, _price, _cost, _min, _initial]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final repo = ref.read(gymRepositoryProvider);
    try {
      final id = await repo.saveProduct(
        ProductInput(
          name: _name.text.trim(),
          sku: _opt(_sku),
          priceCents: parseMoney(_price.text)!,
          // Sin permiso de costos no se envía: el costo guardado no cambia.
          costCents: ref.read(canProvider(Perm.inventoryCost)) ? parseMoney(_cost.text.isEmpty ? '0' : _cost.text)! : null,
          minStock: int.parse(_min.text),
          supplierId: _supplierId,
          active: _active,
        ),
        id: widget.product?.id,
      );
      final initial = int.tryParse(_initial.text) ?? 0;
      if (widget.product == null && initial > 0) {
        await repo.addStock(id, initial, note: 'Stock inicial');
      }
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Producto guardado');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo guardar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.product != null;
    final suppliers = ref.watch(suppliersProvider).value ?? const <Supplier>[];

    String? money(String? v) => parseMoney(v ?? '') == null ? 'Monto inválido' : null;
    return FormDialog(
      title: editing ? 'Editar producto' : 'Nuevo producto',
      subtitle: editing ? 'El stock se cambia con “Entrada / ajuste de stock”' : null,
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
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Ingresa un nombre' : null,
            ),
            Row(
              spacing: 14,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _sku,
                    decoration: InputDecoration(
                      labelText: 'Código (SKU)',
                      suffixIcon: ScanButton(onScanned: _onScanned),
                    ),
                    validator: (v) {
                      final code = (v ?? '').trim().toLowerCase();
                      if (code.isEmpty) return null;
                      final products = ref.read(productsProvider).value ?? const <Product>[];
                      final clash = products.where((p) => p.id != widget.product?.id && p.sku?.toLowerCase() == code).firstOrNull;
                      return clash == null ? null : 'Ya es de ${clash.name}';
                    },
                  ),
                ),
                Expanded(
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
              ],
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
                if (ref.watch(canProvider(Perm.inventoryCost)))
                  Expanded(
                    child: TextFormField(
                      controller: _cost,
                      decoration: const InputDecoration(labelText: 'Costo', prefixText: '$currencySymbol '),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [MoneyInputFormatter()],
                      validator: (v) => (v ?? '').trim().isEmpty ? null : money(v),
                    ),
                  ),
              ],
            ),
            Row(
              spacing: 14,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _min,
                    decoration: const InputDecoration(labelText: 'Stock mínimo', helperText: 'Avisa cuando quede esto o menos'),
                    keyboardType: TextInputType.number,
                    inputFormatters: digitsOnly,
                    validator: (v) => int.tryParse(v ?? '') == null ? 'Número inválido' : null,
                  ),
                ),
                Expanded(
                  child: editing
                      ? SwitchListTile(
                          value: _active,
                          onChanged: (v) => setState(() => _active = v),
                          contentPadding: EdgeInsets.zero,
                          title: const Text('A la venta'),
                        )
                      : TextFormField(
                          controller: _initial,
                          decoration: const InputDecoration(labelText: 'Stock inicial', helperText: 'Luego se repone con Compras'),
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

/// Ajuste de inventario: conteo físico que no cuadra, merma, vencidos,
/// regalos. La mercancía nueva entra por Compras (queda la factura).
class _StockDialog extends ConsumerStatefulWidget {
  const _StockDialog({required this.product});

  final Product product;

  @override
  ConsumerState<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends ConsumerState<_StockDialog> {
  final _form = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _note = TextEditingController();
  bool _subtract = true; // la mayoría de los ajustes son mermas
  bool _busy = false;

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final qty = int.parse(_qty.text);
    try {
      final stock = await ref.read(gymRepositoryProvider).addStock(widget.product.id, _subtract ? -qty : qty, note: _opt(_note));
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, '${widget.product.name}: stock ajustado a $stock');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo ajustar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return FormDialog(
      title: 'Ajuste de inventario',
      subtitle: '${p.name} · stock actual ${p.stock}',
      width: 480,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(_subtract ? 'Restar del stock' : 'Sumar al stock')),
      ],
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 14,
          children: [
            Text(
              'Para mercancía nueva usa Compras: así queda la factura y el costo.',
              style: AppText.mono(size: 12, color: AppColors.textMuted),
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Restar (merma)'), selected: _subtract, onSelected: (_) => setState(() => _subtract = true)),
                ChoiceChip(
                  label: const Text('Sumar (sobrante)'),
                  selected: !_subtract,
                  onSelected: (_) => setState(() => _subtract = false),
                ),
              ],
            ),
            TextFormField(
              controller: _qty,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _subtract ? 'Unidades a restar *' : 'Unidades a sumar *'),
              inputFormatters: digitsOnly,
              validator: (v) {
                final n = int.tryParse(v ?? '') ?? 0;
                if (n <= 0) return 'Mayor que cero';
                if (_subtract && n > p.stock) return 'Solo hay ${p.stock}';
                return null;
              },
            ),
            TextFormField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Motivo *', hintText: 'Ej. producto vencido, conteo físico'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Indica el motivo del ajuste' : null,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showSupplierForm(BuildContext context, {Supplier? supplier}) => showDialog(
  context: context,
  builder: (_) => _SupplierForm(supplier: supplier),
);

class _SupplierForm extends ConsumerStatefulWidget {
  const _SupplierForm({this.supplier});

  final Supplier? supplier;

  @override
  ConsumerState<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends ConsumerState<_SupplierForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name);
  late final _phone = TextEditingController(text: onlyDigits(widget.supplier?.phone).isEmpty ? '' : formatPhone(widget.supplier?.phone));
  late final _email = TextEditingController(text: widget.supplier?.email);
  late final _notes = TextEditingController(text: widget.supplier?.notes);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(gymRepositoryProvider)
          .saveSupplier(
            SupplierInput(
              name: _name.text.trim(),
              phone: onlyDigits(_phone.text).isEmpty ? null : onlyDigits(_phone.text),
              email: _opt(_email),
              notes: _opt(_notes),
            ),
            id: widget.supplier?.id,
          );
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, 'Proveedor guardado');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo guardar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.supplier == null ? 'Nuevo proveedor' : 'Editar proveedor',
      width: 480,
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
              decoration: const InputDecoration(labelText: 'Nombre *'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Ingresa un nombre' : null,
            ),
            Row(
              spacing: 14,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Teléfono', hintText: '0212-555-0101'),
                    keyboardType: TextInputType.phone,
                    inputFormatters: const [PhoneInputFormatter()],
                  ),
                ),
                Expanded(
                  child: TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Correo'),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas'),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }
}
