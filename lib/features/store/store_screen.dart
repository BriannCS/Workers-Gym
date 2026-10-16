// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../data/rates.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../payments/method_picker.dart';

/// Venta en curso. Vive en un provider para que el ticket (panel lateral en
/// escritorio, hoja inferior en teléfono) y el catálogo compartan el mismo
/// carrito, y para no perderlo al cambiar de sección.
class CartState {
  const CartState({this.quantities = const {}, this.member, this.method});

  final Map<String, int> quantities; // productId -> cantidad
  final Member? member;
  final PaymentMethod? method; // null = el primer método activo

  int get items => quantities.values.fold(0, (s, q) => s + q);

  List<CartLine> lines(Map<String, Product> byId) => [
        for (final MapEntry(key: id, value: q) in quantities.entries)
          if (byId[id] != null) CartLine(byId[id]!, q),
      ];
}

class CartController extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(Product p, int delta) {
    final qty = (state.quantities[p.id] ?? 0) + delta;
    if (qty > p.stock) return;
    final next = {...state.quantities}..remove(p.id);
    if (qty > 0) next[p.id] = qty;
    state = CartState(quantities: next, member: state.member, method: state.method);
  }

  void setMember(Member? m) => state = CartState(quantities: state.quantities, member: m, method: state.method);
  void setMethod(PaymentMethod m) => state = CartState(quantities: state.quantities, member: state.member, method: m);
  void clear() => state = CartState(method: state.method);
}

final cartProvider = NotifierProvider<CartController, CartState>(CartController.new);

class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({super.key});

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(productsProvider);
    final cart = ref.watch(cartProvider);

    final catalog = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          decoration: const InputDecoration(hintText: 'Buscar producto o código', prefixIcon: Icon(Icons.search, size: 20)),
        ),
        const SizedBox(height: 20),
        AsyncView(
          products,
          onRetry: () => ref.invalidate(productsProvider),
          data: (list) {
            final visible = list
                .where((p) => p.active && (p.name.toLowerCase().contains(_query) || (p.sku?.toLowerCase().contains(_query) ?? false)))
                .toList();
            if (visible.isEmpty) {
              return const EmptyState(icon: Icons.sell_outlined, title: 'Sin productos', message: 'Agrégalos en Inventario.');
            }
            return ResponsiveGrid(
              minItemWidth: context.isPhone ? 150 : 180,
              spacing: 14,
              children: [
                for (final p in visible)
                  _PriceTag(
                    product: p,
                    inCart: cart.quantities[p.id] ?? 0,
                    onTap: () => ref.read(cartProvider.notifier).add(p, 1),
                  ),
              ],
            );
          },
        ),
      ],
    );

    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 980;
      final body = PageBody(
        header: const PageHeader(title: 'Tienda', subtitle: 'Mostrador de venta'),
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 32,
              children: [
                Expanded(flex: 3, child: catalog),
                const Expanded(flex: 2, child: Column(spacing: 28, children: [_Receipt(), _TodaySales()])),
              ],
            )
          else ...[
            catalog,
            const SizedBox(height: 28),
            const _TodaySales(),
            if (cart.items > 0) const SizedBox(height: 72),
          ],
        ],
      );
      if (wide || cart.items == 0) return body;
      return Stack(children: [body, const Positioned(left: 0, right: 0, bottom: 0, child: _CartBar())]);
    });
  }
}

// ---------------------------------------------------------------------------
// Etiqueta de precio

class _PriceTag extends StatelessWidget {
  const _PriceTag({required this.product, required this.inCart, required this.onTap});

  final Product product;
  final int inCart;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final available = p.stock - inCart > 0;
    final (stockText, stockColor) = switch (p.stock) {
      0 => ('AGOTADO', AppColors.danger),
      _ when p.lowStock => ('QUEDAN ${p.stock}', AppColors.warning),
      _ => ('${p.stock} EN STOCK', AppColors.textMuted),
    };
    final selected = inCart > 0;
    return Opacity(
      opacity: p.stock == 0 ? .55 : 1,
      child: CustomPaint(
        painter: _TagPainter(fill: selected ? AppColors.ink : AppColors.surface, stroke: AppColors.ink),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: available ? onTap : null,
            customBorder: _TagShape(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          p.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.25, color: selected ? AppColors.surface : AppColors.ink),
                        ),
                      ),
                      if (selected)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                          color: AppColors.plateYellow,
                          child: Text('x$inCart', style: AppText.mono(size: 12, weight: FontWeight.w600)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(formatMoney(p.priceCents), style: AppText.score(30, color: selected ? AppColors.surface : AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(stockText, style: AppText.mono(size: 10.5, weight: FontWeight.w600, color: selected ? AppColors.plateYellow : stockColor)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Silueta de etiqueta colgante: esquinas izquierdas cortadas y perforación.
Path _tagPath(Rect r) {
  const cut = 14.0;
  return Path()
    ..moveTo(r.left + cut, r.top)
    ..lineTo(r.right, r.top)
    ..lineTo(r.right, r.bottom)
    ..lineTo(r.left + cut, r.bottom)
    ..lineTo(r.left, r.bottom - cut)
    ..lineTo(r.left, r.top + cut)
    ..close();
}

class _TagShape extends ShapeBorder {
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _tagPath(rect);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _tagPath(rect);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}

class _TagPainter extends CustomPainter {
  const _TagPainter({required this.fill, required this.stroke});

  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final path = _tagPath(Offset.zero & size);
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(path, Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3);
    // Perforación del cordel.
    final hole = Offset(15, size.height / 2);
    canvas.drawCircle(hole, 4.5, Paint()..color = AppColors.bg);
    canvas.drawCircle(hole, 4.5, Paint()
      ..color = fill == AppColors.ink ? AppColors.surface : stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
  }

  @override
  bool shouldRepaint(_TagPainter old) => old.fill != fill || old.stroke != stroke;
}

// ---------------------------------------------------------------------------
// Ticket de la venta en curso

class _Receipt extends ConsumerStatefulWidget {
  const _Receipt({this.inSheet = false});

  final bool inSheet;

  @override
  ConsumerState<_Receipt> createState() => _ReceiptState();
}

class _ReceiptState extends ConsumerState<_Receipt> {
  bool _busy = false;

  Future<void> _checkout(List<CartLine> lines, CartState cart, PaymentMethod method, ExchangeRate? rate) async {
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).registerSale(lines, method, memberId: cart.member?.id, rate: rate);
      refreshGymData(ref);
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      if (widget.inSheet) Navigator.pop(context);
      final total = cartTotal(lines);
      showToast(context, 'Venta registrada · ${method.inBolivares && rate != null ? formatVes(rate.vesCents(total)) : formatMoney(total)}');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo registrar la venta: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final lines = cart.lines({for (final p in products) p.id: p});
    final total = cartTotal(lines);
    final method = cart.method ?? activeMethods(ref).firstOrNull;
    final rate = ref.watch(currentRateProvider).value;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: widget.inSheet ? null : Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('VENTA EN CURSO', style: AppText.label.copyWith(color: AppColors.ink, fontWeight: FontWeight.w600))),
              if (lines.isNotEmpty) TextButton(onPressed: notifier.clear, child: const Text('Vaciar')),
            ],
          ),
          const SizedBox(height: 6),
          const Perforation(),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text('Toca una etiqueta para agregarla.', style: AppText.mono(size: 12.5, color: AppColors.textMuted), textAlign: TextAlign.center),
            )
          else
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    _Step(icon: Icons.remove, tooltip: 'Quitar uno', onTap: () => notifier.add(l.product, -1)),
                    SizedBox(width: 30, child: Text('${l.quantity}', textAlign: TextAlign.center, style: AppText.mono(size: 14, weight: FontWeight.w600))),
                    _Step(icon: Icons.add, tooltip: 'Agregar uno', onTap: l.quantity < l.product.stock ? () => notifier.add(l.product, 1) : null),
                    const SizedBox(width: 10),
                    Expanded(child: Text(l.product.name, style: AppText.mono(size: 12.5), overflow: TextOverflow.ellipsis)),
                    Text(formatMoney(l.totalCents), style: AppText.mono(size: 13, weight: FontWeight.w600)),
                  ],
                ),
              ),
          const SizedBox(height: 10),
          const Perforation(),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('TOTAL', style: AppText.label.copyWith(color: AppColors.ink, fontSize: 13)),
              const Spacer(),
              Text(formatMoney(total), style: AppText.score(48)),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, c) => DropdownMenu<Member?>(
              key: ValueKey(cart.member?.id),
              width: c.maxWidth,
              initialSelection: cart.member,
              enableFilter: true,
              requestFocusOnTap: true,
              menuHeight: 280,
              hintText: 'Cliente (opcional)',
              leadingIcon: const Icon(Icons.person_outline, size: 20),
              onSelected: notifier.setMember,
              dropdownMenuEntries: [for (final m in members) DropdownMenuEntry(value: m, label: m.fullName)],
            ),
          ),
          const SizedBox(height: 12),
          MethodPicker(selected: method, onChanged: notifier.setMethod),
          if (lines.isNotEmpty) BolivarCharge(usdCents: total, method: method),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: lines.isEmpty || method == null || (method.inBolivares && rate == null) || _busy
                ? null
                : () => _checkout(lines, cart, method, rate),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
            child: Text(lines.isEmpty ? 'Cobrar' : chargeLabel(total, method, rate)),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        style: IconButton.styleFrom(side: const BorderSide(color: AppColors.borderStrong)),
        icon: Icon(icon, size: 16),
      );
}

/// Teléfono: resumen fijo abajo que abre el ticket.
class _CartBar extends ConsumerWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final total = cartTotal(cart.lines({for (final p in products) p.id: p}));
    return Material(
      color: AppColors.ink,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const SafeArea(child: SingleChildScrollView(child: _Receipt(inSheet: true))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Text('${cart.items} ${cart.items == 1 ? 'ARTÍCULO' : 'ARTÍCULOS'}', style: AppText.label.copyWith(color: AppColors.surface)),
              const Spacer(),
              Text(formatMoney(total), style: AppText.score(28, color: AppColors.surface)),
              const SizedBox(width: 12),
              const Icon(Icons.expand_less, color: AppColors.surface),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ventas del día

class _TodaySales extends ConsumerWidget {
  const _TodaySales();

  Future<void> _void(BuildContext context, WidgetRef ref, Sale s) async {
    final reason = await askVoidReason(context, title: 'Anular venta', detail: '${s.description} · ${formatMoney(s.totalCents)}. El stock se devuelve.');
    if (reason == null) return;
    try {
      await ref.read(gymRepositoryProvider).voidSale(s.id, reason);
      refreshGymData(ref);
      if (context.mounted) showToast(context, 'Venta anulada, stock devuelto');
    } catch (e) {
      if (context.mounted) showToast(context, 'No se pudo anular: ${friendlyError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dateOnly(ref.watch(clockProvider)());
    final sales = ref.watch(salesProvider);
    return Panel(
      title: 'Ventas de hoy',
      padding: EdgeInsets.zero,
      child: AsyncView(
        sales,
        onRetry: () => ref.invalidate(salesProvider),
        data: (list) {
          final todays = list.where((s) => dateOnly(s.soldAt) == today).toList();
          if (todays.isEmpty) return const EmptyState(icon: Icons.point_of_sale, title: 'Sin ventas hoy');
          return Column(
            children: [
              for (final s in todays)
                Opacity(
                  opacity: s.voided ? .5 : 1,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(20, 10, 6, 10),
                    decoration: const BoxDecoration(border: rowRule),
                    child: Row(
                      children: [
                        SizedBox(width: 50, child: Text(formatTime(s.soldAt), style: AppText.mono(size: 12.5, color: AppColors.plateBlue))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.description, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
                              Text(
                                s.voided ? 'ANULADA: ${s.voidReason}' : [s.methodName, ?s.memberName].join(' · '),
                                style: AppText.mono(size: 11.5, color: s.voided ? AppColors.danger : AppColors.textMuted),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(s.totalCents),
                          style: AppText.mono(size: 13, weight: FontWeight.w600).copyWith(decoration: s.voided ? TextDecoration.lineThrough : null),
                        ),
                        SizedBox(
                          width: 44,
                          child: s.voided || !ref.watch(canProvider(Perm.salesVoid))
                              ? null
                              : IconButton(tooltip: 'Anular venta', onPressed: () => _void(context, ref, s), icon: const Icon(Icons.block, size: 18)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
