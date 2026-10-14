// Hecho por Briann$ Workers Corp.
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart' show ImageProvider, MemoryImage;

import '../domain/models.dart';
import 'gym_repository.dart';

/// Repositorio en memoria con datos de ejemplo. Se usa cuando no hay
/// credenciales de Supabase y en los tests. Replica las reglas de las
/// funciones SQL (cobros, ventas, compras, anulaciones, stock).
class DemoGymRepository implements GymRepository {
  DemoGymRepository.seeded({this.clock = DateTime.now}) : _now = clock() {
    _seed();
  }

  final DateTime Function() clock;
  final DateTime _now;
  final _plans = <Plan>[];
  final _members = <Member>[];
  final _photos = <String, Uint8List>{};
  final _methods = <PaymentMethod>[];
  var _settings = const GymSettings();
  final _payments = <Payment>[];
  final _attendance = <Attendance>[];
  final _suppliers = <Supplier>[];
  final _products = <Product>[];
  final _sales = <Sale>[];
  final _purchases = <Purchase>[];

  /// Stock inicial y ajustes (equivale a `stock_entries`).
  final _stockEntries = <(String productId, int quantity)>[];
  int _nextId = 1;

  /// Tasa fija para los datos de ejemplo cobrados en bolívares.
  static const demoRate = ExchangeRate(RateSource.bcvUsd, 876.80);

  String _id() => 'demo-${_nextId++}';
  DateTime get _today => dateOnly(_now);

  void _seed() {
    _methods.addAll(const [
      PaymentMethod(code: 'efectivo_usd', name: r'Efectivo ($)', currency: Currency.usd, position: 1),
      PaymentMethod(code: 'efectivo_bs', name: 'Efectivo (Bs.)', currency: Currency.ves, position: 2),
      PaymentMethod(code: 'transferencia', name: 'Transferencia', currency: Currency.ves, position: 3),
      PaymentMethod(code: 'pago_movil', name: 'Pago móvil', currency: Currency.ves, position: 4),
      PaymentMethod(code: 'binance', name: 'Binance', currency: Currency.usd, position: 5),
      PaymentMethod(code: 'zelle', name: 'Zelle', currency: Currency.usd, position: 6),
    ]);
    PaymentMethod method(String code) => _methods.firstWhere((m) => m.code == code);
    final rotation = [method('efectivo_usd'), method('pago_movil'), method('zelle'), method('transferencia')];

    _plans.addAll([
      Plan(id: _id(), name: 'Pase diario', priceCents: 300, durationDays: 1),
      Plan(id: _id(), name: 'Mensual', priceCents: 3000, durationDays: 30),
      Plan(id: _id(), name: 'Trimestral', priceCents: 8000, durationDays: 90),
      Plan(id: _id(), name: 'Anual', priceCents: 28000, durationDays: 365),
      Plan(id: _id(), name: 'Estudiante', priceCents: 2000, durationDays: 30, active: false),
    ]);
    final monthly = _plans[1], quarterly = _plans[2], yearly = _plans[3];

    // (nombre, cédula, teléfono, plan, días que faltan para vencer; null = nunca pagó)
    final seed = <(String, String, String, Plan?, int?)>[
      ('María Fernanda Rojas', 'V-24518330', '04145550192', monthly, 21),
      ('Carlos Eduardo Pérez', 'V-19204877', '04125550148', quarterly, 64),
      ('Andrea Valentina Gómez', 'V-27901442', '04245550110', monthly, 2),
      ('Luis Alberto Méndez', 'V-15330921', '04165550173', monthly, -4),
      ('Gabriela Sofía Herrera', 'V-26118005', '04145550131', yearly, 200),
      ('José Miguel Castillo', 'V-21447690', '04125550167', monthly, 0),
      ('Daniela Carolina Suárez', 'V-28662017', '04245550185', monthly, 12),
      ('Ricardo Antonio Díaz', 'E-81093554', '04145550129', quarterly, -18),
      ('Valeria Isabel Torres', 'V-29310876', '04165550154', monthly, 27),
      ('Miguel Ángel Ramírez', 'V-22785113', '04125550106', monthly, 3),
      ('Camila Alejandra Núñez', 'V-30126448', '04245550199', null, null),
      ('Fernando José Morales', 'V-18559230', '04145550140', monthly, 8),
      ('Isabella Lucía Vargas', 'V-27004681', '04125550177', quarterly, 41),
      ('Andrés Felipe Ortega', 'V-20931502', '04165550115', monthly, -1),
    ];

    for (final (i, (name, doc, phone, plan, left)) in seed.indexed) {
      final member = Member(
        id: _id(),
        fullName: name,
        documentId: doc,
        phone: phone,
        createdAt: _now.subtract(Duration(days: 400 - i * 25)),
      );
      _members.add(member);
      if (plan == null || left == null) continue;

      // Dos pagos consecutivos para que el historial tenga contenido.
      final end = _today.add(Duration(days: left));
      final start = end.subtract(Duration(days: plan.durationDays - 1));
      final prevEnd = start.subtract(const Duration(days: 1));
      for (final (k, (s, e)) in [
        (prevEnd.subtract(Duration(days: plan.durationDays - 1)), prevEnd),
        (start, end),
      ].indexed) {
        final paidAt = s.isAfter(_now) ? _now.subtract(Duration(hours: i + 1)) : DateTime(s.year, s.month, s.day, 8 + i % 10, 15);
        final m = rotation[(i + k) % rotation.length];
        _payments.add(Payment(
          id: _id(),
          memberId: member.id,
          memberName: name,
          planId: plan.id,
          planName: plan.name,
          amountCents: plan.priceCents,
          methodCode: m.code,
          methodName: m.name,
          periodStart: s,
          periodEnd: e,
          paidAt: paidAt,
          currency: m.currency,
          rate: m.inBolivares ? demoRate.value : null,
          rateSource: m.inBolivares ? demoRate.source : null,
          amountVesCents: m.inBolivares ? demoRate.vesCents(plan.priceCents) : null,
        ));
      }
    }

    _suppliers.addAll([
      Supplier(id: _id(), name: 'Distribuidora Andes', phone: '02125550101', email: 'ventas@andes.test'),
      Supplier(id: _id(), name: 'NutriSport C.A.', phone: '02415550177'),
    ]);
    final (drinks, supplements) = (_suppliers[0].id, _suppliers[1].id);

    // (nombre, código, precio, costo, stock final deseado, mínimo, proveedor)
    final catalog = [
      ('Agua mineral 600 ml', 'AGU-600', 100, 45, 48, 12, drinks),
      ('Bebida isotónica', 'ISO-500', 250, 140, 20, 6, drinks),
      ('Barra de proteína', 'BAR-PRO', 300, 170, 4, 8, supplements),
      ('Proteína whey (servicio)', 'WHEY-1', 200, 90, 30, 5, supplements),
      ('Creatina 300 g', 'CREA-300', 3500, 2200, 3, 2, supplements),
      ('Shaker 700 ml', 'SHK-700', 800, 350, 0, 3, supplements),
      ('Toalla deportiva', 'TOA-01', 1200, 600, 9, 2, null),
      ('Guantes de entrenamiento', 'GUA-M', 1500, 750, 5, 2, null),
    ];
    for (final (name, sku, price, cost, _, min, supplier) in catalog) {
      _products.add(Product(id: _id(), name: name, sku: sku, priceCents: price, costCents: cost, stock: 0, minStock: min, supplierId: supplier));
    }

    // Ventas de ejemplo (índice de producto, cantidad): este mes y hoy, una anulada.
    final seedSales = [
      (0, 8, [(0, 2)], 'efectivo_usd', false),
      (0, 9, [(1, 1), (2, 1)], 'pago_movil', false),
      (0, 7, [(3, 1)], 'efectivo_usd', true),
      (1, 18, [(6, 1)], 'transferencia', false),
      (3, 17, [(4, 1)], 'zelle', false),
      (6, 19, [(0, 3), (1, 2)], 'efectivo_bs', false),
    ];
    final soldQty = <int, int>{};
    for (final (daysAgo, hour, lines, _, voided) in seedSales) {
      if (voided || DateTime(_now.year, _now.month, _now.day - daysAgo, hour, 20).isAfter(_now)) continue;
      for (final (p, q) in lines) {
        soldQty[p] = (soldQty[p] ?? 0) + q;
      }
    }

    // Compras de ejemplo que dejan el stock deseado tras las ventas:
    // compras − ventas = stock actual.
    for (final (daysAgo, supplier, invoice) in [(12, drinks, 'A-0451'), (9, supplements, 'NS-2207'), (20, null, null)]) {
      final lines = [
        for (final (i, (_, _, _, cost, target, _, s)) in catalog.indexed)
          if (s == supplier && target + (soldQty[i] ?? 0) > 0)
            PurchaseLine(product: _products[i], quantity: target + (soldQty[i] ?? 0), unitCostCents: cost),
      ];
      _applyPurchase(NewPurchase(
        lines: lines,
        supplierId: supplier,
        invoice: invoice,
        purchasedOn: _today.subtract(Duration(days: daysAgo)),
      ), createdAt: _now.subtract(Duration(days: daysAgo)));
    }

    for (final (daysAgo, hour, lines, code, voided) in seedSales) {
      final at = DateTime(_now.year, _now.month, _now.day - daysAgo, hour, 20);
      if (at.isAfter(_now)) continue;
      final m = method(code);
      final items = [
        for (final (p, q) in lines)
          SaleItem(productId: _products[p].id, productName: _products[p].name, quantity: q, unitPriceCents: _products[p].priceCents),
      ];
      final total = items.fold(0, (s, i) => s + i.totalCents);
      if (!voided) {
        for (final item in items) {
          _setStock(item.productId, (s) => s - item.quantity);
        }
      }
      _sales.add(Sale(
        id: _id(),
        methodCode: m.code,
        methodName: m.name,
        totalCents: total,
        soldAt: at,
        items: items,
        currency: m.currency,
        rate: m.inBolivares ? demoRate.value : null,
        rateSource: m.inBolivares ? demoRate.source : null,
        totalVesCents: m.inBolivares ? demoRate.vesCents(total) : null,
        voidedAt: voided ? at.add(const Duration(minutes: 5)) : null,
        voidReason: voided ? 'Cobrado dos veces' : null,
      ));
    }

    final todayStart = DateTime(_now.year, _now.month, _now.day, 6);
    for (final (i, m) in _members.where((m) => _lastPeriodEnd(m.id) != null).take(7).indexed) {
      final at = todayStart.add(Duration(minutes: 35 * i + 7));
      if (at.isBefore(_now)) {
        _attendance.add(Attendance(id: _id(), memberId: m.id, memberName: m.fullName, checkedInAt: at));
      }
    }
  }

  void _setStock(String productId, int Function(int) update, {int? costCents}) {
    final i = _products.indexWhere((p) => p.id == productId);
    _products[i] = _products[i].withStock(update(_products[i].stock), costCents: costCents);
  }

  /// Stock calculado desde los registros (igual que la vista SQL
  /// `product_stock_audit`): inicial ± ajustes + compras − ventas.
  Map<String, int> computedStock() => {
        for (final p in _products)
          p.id: _stockEntries.where((e) => e.$1 == p.id).fold<int>(0, (s, e) => s + e.$2) +
              _purchases.where((x) => !x.voided).expand((x) => x.items).where((i) => i.productId == p.id).fold<int>(0, (s, i) => s + i.quantity) -
              _sales.where((x) => !x.voided).expand((x) => x.items).where((i) => i.productId == p.id).fold<int>(0, (s, i) => s + i.quantity),
      };

  DateTime? _lastPeriodEnd(String memberId) {
    DateTime? last;
    for (final p in _payments.where((p) => p.memberId == memberId && !p.voided)) {
      if (last == null || p.periodEnd.isAfter(last)) last = p.periodEnd;
    }
    return last;
  }

  Member _withOverview(Member m) {
    final mine = _payments.where((p) => p.memberId == m.id && !p.voided).toList()
      ..sort((a, b) => b.periodEnd.compareTo(a.periodEnd));
    return mine.isEmpty ? m : m.copyWith(expiresOn: mine.first.periodEnd, planName: mine.first.planName);
  }

  static bool _inRange(DateTime t, DateTime? from, DateTime? to) =>
      (from == null || !t.isBefore(from)) && (to == null || t.isBefore(to));

  // -------------------------------------------------------------------------
  // Clientes

  @override
  Future<List<Member>> members() async =>
      (_members.map(_withOverview).toList()..sort((a, b) => a.fullName.compareTo(b.fullName)));

  @override
  Future<Member> createMember(MemberInput input) async {
    if (input.documentId != null && _members.any((m) => m.documentId == input.documentId)) {
      throw const GymException('Ya existe un cliente con esa cédula');
    }
    final m = Member(
      id: _id(),
      fullName: input.fullName,
      documentId: input.documentId,
      phone: input.phone,
      email: input.email,
      notes: input.notes,
      createdAt: clock(),
    );
    _members.add(m);
    return m;
  }

  @override
  Future<void> updateMember(String id, MemberInput input) async {
    final i = _members.indexWhere((m) => m.id == id);
    _members[i] = _members[i].copyWith(input: input);
  }

  @override
  Future<Map<String, ImageProvider>> memberPhotos(List<Member> members) async =>
      {for (final m in members) if (_photos[m.id] case final bytes?) m.id: MemoryImage(bytes)};

  @override
  Future<void> setMemberPhoto(Member member, Uint8List bytes, {String mimeType = 'image/jpeg'}) async {
    _photos[member.id] = bytes;
    final i = _members.indexWhere((m) => m.id == member.id);
    _members[i] = _members[i].copyWith(photoPath: () => 'demo/${member.id}');
  }

  @override
  Future<void> removeMemberPhoto(Member member) async {
    _photos.remove(member.id);
    final i = _members.indexWhere((m) => m.id == member.id);
    _members[i] = _members[i].copyWith(photoPath: () => null);
  }

  // -------------------------------------------------------------------------
  // Planes, métodos de pago, ajustes

  @override
  Future<List<Plan>> plans() async => List.of(_plans)
    ..sort((a, b) => a.active != b.active ? (a.active ? -1 : 1) : a.durationDays.compareTo(b.durationDays));

  @override
  Future<void> savePlan(PlanInput input, {String? id}) async {
    final plan = Plan(
      id: id ?? _id(),
      name: input.name,
      priceCents: input.priceCents,
      durationDays: input.durationDays,
      active: input.active,
    );
    final i = _plans.indexWhere((p) => p.id == id);
    i < 0 ? _plans.add(plan) : _plans[i] = plan;
  }

  @override
  Future<List<PaymentMethod>> paymentMethods() async => List.of(_methods)..sort((a, b) => a.position.compareTo(b.position));

  @override
  Future<void> addPaymentMethod(String name, Currency currency) async {
    if (name.trim().isEmpty) throw const GymException('Escribe el nombre del método');
    final base = methodCodeFor(name);
    var code = base;
    for (var i = 2; _methods.any((m) => m.code == code); i++) {
      code = '${base}_$i';
    }
    _methods.add(PaymentMethod(code: code, name: name.trim(), currency: currency, position: _methods.length + 1));
  }

  @override
  Future<void> setPaymentMethodActive(String code, bool active) async {
    final i = _methods.indexWhere((m) => m.code == code);
    _methods[i] = _methods[i].copyWith(active: active);
  }

  @override
  Future<GymSettings> settings() async => _settings;

  @override
  Future<void> saveSettings(GymSettings settings) async {
    if (settings.rateSource == RateSource.manual && (settings.manualRate ?? 0) <= 0) {
      throw const GymException('Indica una tasa manual mayor que cero');
    }
    _settings = settings;
  }

  PaymentMethod _activeMethod(String code) {
    final m = _methods.where((m) => m.code == code && m.active).firstOrNull;
    if (m == null) throw const GymException('El método de pago no existe o está desactivado');
    return m;
  }

  // -------------------------------------------------------------------------
  // Pagos

  @override
  Future<List<Payment>> payments({String? memberId, DateTime? from, DateTime? to, int limit = 300}) async =>
      (_payments.where((p) => (memberId == null || p.memberId == memberId) && _inRange(p.paidAt, from, to)).toList()
            ..sort((a, b) => b.paidAt.compareTo(a.paidAt)))
          .take(limit)
          .toList();

  /// Igual que `register_payment` en SQL: recalcula el periodo con el estado actual.
  @override
  Future<Payment> addPayment(NewPayment p) async {
    final plan = _plans.firstWhere((x) => x.id == p.plan.id);
    if (!plan.active) throw const GymException('El plan no existe o está archivado');
    final method = _activeMethod(p.method.code);
    if (method.inBolivares && p.rate == null) throw const GymException('Falta la tasa de cambio para cobrar en bolívares');
    final period = renewalPeriod(
      currentExpiresOn: _lastPeriodEnd(p.member.id),
      today: p.today,
      durationDays: plan.durationDays,
    );
    final payment = Payment(
      id: _id(),
      memberId: p.member.id,
      memberName: p.member.fullName,
      planId: plan.id,
      planName: plan.name,
      amountCents: plan.priceCents,
      methodCode: method.code,
      methodName: method.name,
      periodStart: period.start,
      periodEnd: period.end,
      paidAt: clock(),
      currency: method.currency,
      rate: method.inBolivares ? p.rate!.value : null,
      rateSource: method.inBolivares ? p.rate!.source : null,
      amountVesCents: method.inBolivares ? p.rate!.vesCents(plan.priceCents) : null,
    );
    _payments.add(payment);
    return payment;
  }

  @override
  Future<void> voidPayment(String id, String reason) async {
    if (reason.trim().isEmpty) throw const GymException('Indica el motivo de la anulación');
    final i = _payments.indexWhere((p) => p.id == id && !p.voided);
    if (i < 0) throw const GymException('El pago no existe o ya estaba anulado');
    _payments[i] = _payments[i].voidedWith(reason.trim(), clock());
  }

  // -------------------------------------------------------------------------
  // Asistencia

  @override
  Future<List<Attendance>> attendanceSince(DateTime from) async =>
      _attendance.where((a) => !a.checkedInAt.isBefore(from)).toList()
        ..sort((a, b) => b.checkedInAt.compareTo(a.checkedInAt));

  @override
  Future<void> checkIn(String memberId, {CheckInMethod method = CheckInMethod.manual}) async {
    final m = _members.firstWhere((m) => m.id == memberId);
    _attendance.add(Attendance(
      id: _id(),
      memberId: memberId,
      memberName: m.fullName,
      checkedInAt: clock(),
      method: method,
    ));
  }

  // -------------------------------------------------------------------------
  // Tienda

  Product _withSupplier(Product p) {
    final s = _suppliers.where((s) => s.id == p.supplierId).firstOrNull;
    return Product(
      id: p.id,
      name: p.name,
      sku: p.sku,
      priceCents: p.priceCents,
      costCents: p.costCents,
      stock: p.stock,
      minStock: p.minStock,
      supplierId: s?.id,
      supplierName: s?.name,
      active: p.active,
    );
  }

  @override
  Future<List<Supplier>> suppliers() async => List.of(_suppliers)..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<void> saveSupplier(SupplierInput input, {String? id}) async {
    final s = Supplier(id: id ?? _id(), name: input.name, phone: input.phone, email: input.email, notes: input.notes);
    final i = _suppliers.indexWhere((x) => x.id == id);
    i < 0 ? _suppliers.add(s) : _suppliers[i] = s;
  }

  @override
  Future<List<Product>> products() async => _products.map(_withSupplier).toList()
    ..sort((a, b) => a.active != b.active ? (a.active ? -1 : 1) : a.name.compareTo(b.name));

  @override
  Future<String> saveProduct(ProductInput input, {String? id}) async {
    final i = _products.indexWhere((p) => p.id == id);
    if (input.sku != null && _products.any((p) => p.sku == input.sku && p.id != id)) {
      throw const GymException('Ya existe un producto con ese código');
    }
    final p = Product(
      id: id ?? _id(),
      name: input.name,
      sku: input.sku,
      priceCents: input.priceCents,
      costCents: input.costCents,
      stock: i < 0 ? 0 : _products[i].stock,
      minStock: input.minStock,
      supplierId: input.supplierId,
      active: input.active,
    );
    i < 0 ? _products.add(p) : _products[i] = p;
    return p.id;
  }

  @override
  Future<int> addStock(String productId, int quantity, {int? unitCostCents, String? note}) async {
    if (quantity == 0) throw const GymException('La cantidad no puede ser cero');
    if ((note ?? '').trim().isEmpty) throw const GymException('Indica el motivo del ajuste');
    final i = _products.indexWhere((p) => p.id == productId);
    if (i < 0) throw const GymException('El producto no existe');
    final stock = _products[i].stock + quantity;
    if (stock < 0) throw const GymException('El ajuste dejaría el stock en negativo');
    _products[i] = _products[i].withStock(stock, costCents: unitCostCents);
    _stockEntries.add((productId, quantity));
    return stock;
  }

  @override
  Future<List<Sale>> sales({DateTime? from, DateTime? to, int limit = 200}) async =>
      (_sales.where((s) => _inRange(s.soldAt, from, to)).toList()..sort((a, b) => b.soldAt.compareTo(a.soldAt)))
          .take(limit)
          .toList();

  /// Igual que `register_sale` en SQL: todo o nada, precios desde el catálogo.
  @override
  Future<String> registerSale(List<CartLine> lines, PaymentMethod method, {String? memberId, ExchangeRate? rate}) async {
    if (lines.isEmpty) throw const GymException('La venta no tiene productos');
    final m = _activeMethod(method.code);
    if (m.inBolivares && rate == null) throw const GymException('Falta la tasa de cambio para cobrar en bolívares');
    final qty = <String, int>{};
    for (final l in lines) {
      qty[l.product.id] = (qty[l.product.id] ?? 0) + l.quantity;
    }
    final items = <SaleItem>[];
    for (final MapEntry(key: id, value: q) in qty.entries) {
      final p = _products.firstWhere((p) => p.id == id);
      if (q <= 0) throw const GymException('Cantidad inválida');
      if (!p.active || p.stock < q) throw GymException('Stock insuficiente de ${p.name} (quedan ${p.stock})');
      items.add(SaleItem(productId: id, productName: p.name, quantity: q, unitPriceCents: p.priceCents));
    }
    for (final item in items) {
      _setStock(item.productId, (s) => s - item.quantity);
    }
    final total = items.fold(0, (s, i) => s + i.totalCents);
    final sale = Sale(
      id: _id(),
      memberId: memberId,
      memberName: _members.where((m) => m.id == memberId).firstOrNull?.fullName,
      methodCode: m.code,
      methodName: m.name,
      totalCents: total,
      soldAt: clock(),
      items: items,
      currency: m.currency,
      rate: m.inBolivares ? rate!.value : null,
      rateSource: m.inBolivares ? rate!.source : null,
      totalVesCents: m.inBolivares ? rate!.vesCents(total) : null,
    );
    _sales.add(sale);
    return sale.id;
  }

  @override
  Future<void> voidSale(String id, String reason) async {
    if (reason.trim().isEmpty) throw const GymException('Indica el motivo de la anulación');
    final i = _sales.indexWhere((s) => s.id == id && !s.voided);
    if (i < 0) throw const GymException('La venta no existe o ya estaba anulada');
    _sales[i] = _sales[i].voidedWith(reason.trim(), clock());
    for (final item in _sales[i].items) {
      _setStock(item.productId, (s) => s + item.quantity);
    }
  }

  // -------------------------------------------------------------------------
  // Compras

  @override
  Future<List<Purchase>> purchases({DateTime? from, DateTime? to, int limit = 200}) async => (_purchases
          .where((p) => _inRange(p.purchasedOn, from == null ? null : dateOnly(from), to == null ? null : dateOnly(to)))
          .toList()
        ..sort((a, b) => b.purchasedOn != a.purchasedOn ? b.purchasedOn.compareTo(a.purchasedOn) : b.createdAt.compareTo(a.createdAt)))
      .take(limit)
      .toList();

  /// Igual que `register_purchase` en SQL: suma stock y actualiza el costo.
  @override
  Future<String> registerPurchase(NewPurchase p) async => _applyPurchase(p, createdAt: clock()).id;

  Purchase _applyPurchase(NewPurchase p, {required DateTime createdAt}) {
    if (p.lines.isEmpty) throw const GymException('La compra no tiene productos');
    for (final l in p.lines) {
      if (l.quantity <= 0 || l.unitCostCents < 0) throw const GymException('Cantidad o costo inválido');
    }
    for (final l in p.lines) {
      _setStock(l.product.id, (s) => s + l.quantity, costCents: l.unitCostCents);
    }
    final purchase = Purchase(
      id: _id(),
      supplierId: p.supplierId,
      supplierName: _suppliers.where((s) => s.id == p.supplierId).firstOrNull?.name,
      invoice: p.invoice,
      purchasedOn: dateOnly(p.purchasedOn),
      notes: p.notes,
      totalCents: p.totalCents,
      items: [
        for (final l in p.lines)
          PurchaseItem(productId: l.product.id, productName: l.product.name, quantity: l.quantity, unitCostCents: l.unitCostCents),
      ],
      createdAt: createdAt,
    );
    _purchases.add(purchase);
    return purchase;
  }

  /// Igual que `void_purchase` en SQL: no se puede si ya se vendió parte.
  @override
  Future<void> voidPurchase(String id, String reason) async {
    if (reason.trim().isEmpty) throw const GymException('Indica el motivo de la anulación');
    final i = _purchases.indexWhere((p) => p.id == id && !p.voided);
    if (i < 0) throw const GymException('La compra no existe o ya estaba anulada');
    final qty = <String, int>{};
    for (final item in _purchases[i].items) {
      qty[item.productId] = (qty[item.productId] ?? 0) + item.quantity;
    }
    for (final MapEntry(key: productId, value: q) in qty.entries) {
      final p = _products.firstWhere((p) => p.id == productId);
      if (p.stock < q) throw GymException('No se puede anular: ya se vendieron unidades de ${p.name} (quedan ${p.stock})');
    }
    for (final MapEntry(key: productId, value: q) in qty.entries) {
      _setStock(productId, (s) => s - q);
    }
    _purchases[i] = _purchases[i].voidedWith(reason.trim(), clock());
  }
}
