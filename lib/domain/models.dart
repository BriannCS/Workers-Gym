// Hecho por Briann$ Workers Corp.
/// Entidades del gimnasio y reglas de negocio puras (sin dependencias de UI ni
/// de base de datos). El dinero siempre va en centavos; los precios están en
/// dólares y, si se cobra en bolívares, se guarda la tasa usada.
library;

/// Días antes del vencimiento en que un cliente pasa a "por vencer".
const expiringSoonDays = 3;

/// Normaliza a medianoche UTC para comparar días de calendario sin que las
/// horas o los cambios de horario alteren la cuenta.
DateTime dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

enum MembershipStatus {
  active('Al día'),
  expiringSoon('Po1r vencer'),
  expired('Vencido'),
  none('Sin plan'),
  /// Marcado a mano por recepción (dejó de venir). No cuenta en los avisos de
  /// vencimiento; si vuelve a pagar se reactiva solo.
  inactive('Inactivo');

  const MembershipStatus(this.label);
  final String label;
}

/// Días que faltan para [expiresOn] (último día válido, inclusive).
/// 0 = vence hoy, negativo = ya venció.
int daysLeft(DateTime expiresOn, DateTime today) =>
    dateOnly(expiresOn).difference(dateOnly(today)).inDays;

MembershipStatus membershipStatus(DateTime? expiresOn, DateTime today) {
  if (expiresOn == null) return MembershipStatus.none;
  final left = daysLeft(expiresOn, today);
  if (left < 0) return MembershipStatus.expired;
  if (left <= expiringSoonDays) return MembershipStatus.expiringSoon;
  return MembershipStatus.active;
}

/// Periodo que cubre un pago nuevo. Si la membresía sigue vigente, el nuevo
/// periodo empieza al día siguiente del vencimiento (no se pierden días);
/// si ya venció o no existe, empieza hoy.
({DateTime start, DateTime end}) renewalPeriod({
  required DateTime? currentExpiresOn,
  required DateTime today,
  required int durationDays,
}) {
  final t = dateOnly(today);
  final start = currentExpiresOn != null && !dateOnly(currentExpiresOn).isBefore(t)
      ? dateOnly(currentExpiresOn).add(const Duration(days: 1))
      : t;
  return (start: start, end: start.add(Duration(days: durationDays - 1)));
}

DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
DateTime? _timestamp(Object? v) => v == null ? null : DateTime.parse(v as String).toLocal();
double? _num(Object? v) => v == null ? null : (v is num ? v.toDouble() : double.parse('$v'));
int? _int(Object? v) => v == null ? null : (v is num ? v.round() : int.parse('$v'));

/// Fecha en formato `YYYY-MM-DD` para columnas `date` de Postgres.
String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

/// Solo los dígitos de un texto (cédula, teléfono).
String onlyDigits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

/// Error de negocio con mensaje listo para mostrar (stock insuficiente, etc.).
class GymException implements Exception {
  const GymException(this.message);
  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Moneda, métodos de pago y tasa

enum Currency {
  usd('USD', r'$'),
  ves('VES', 'Bs.');

  const Currency(this.code, this.symbol);
  final String code;
  final String symbol;

  static Currency fromCode(String? code) => code == 'VES' ? ves : usd;
}

class PaymentMethod {
  const PaymentMethod({
    required this.code,
    required this.name,
    required this.currency,
    this.active = true,
    this.position = 0,
  });

  final String code;
  final String name;
  final Currency currency;
  final bool active;
  final int position;

  bool get inBolivares => currency == Currency.ves;

  factory PaymentMethod.fromJson(Map<String, dynamic> j) => PaymentMethod(
        code: j['code'] as String,
        name: j['name'] as String,
        currency: Currency.fromCode(j['currency'] as String?),
        active: j['active'] as bool? ?? true,
        position: j['position'] as int? ?? 0,
      );

  PaymentMethod copyWith({bool? active}) =>
      PaymentMethod(code: code, name: name, currency: currency, active: active ?? this.active, position: position);
}

/// Código estable para un método nuevo a partir de su nombre:
/// "Pago móvil BDV" → "pago_movil_bdv".
String methodCodeFor(String name) {
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final lower = name.trim().toLowerCase().split('').map((c) => accents[c] ?? c).join();
  final code = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return code.length < 2 ? 'metodo_$code' : (code.length > 40 ? code.substring(0, 40) : code);
}

/// De dónde sale la tasa Bs/USD con la que se cobra.
enum RateSource {
  bcvUsd('bcv_usd', 'BCV dólar'),
  bcvEur('bcv_eur', 'BCV euro'),
  paralelo('paralelo', 'Paralelo'),
  manual('manual', 'Manual');

  const RateSource(this.code, this.label);
  final String code;
  final String label;

  static RateSource fromCode(String? code) => values.firstWhere((s) => s.code == code, orElse: () => bcvUsd);
}

/// Bolívares por unidad (dólar o euro, según la fuente).
class ExchangeRate {
  const ExchangeRate(this.source, this.value, {this.updatedAt});

  final RateSource source;
  final double value;
  final DateTime? updatedAt;

  /// Convierte un precio en centavos de dólar a centavos de bolívar.
  int vesCents(int usdCents) => (usdCents * value).round();
}

/// Ajustes compartidos entre dispositivos (tabla `settings`).
class GymSettings {
  const GymSettings({this.rateSource = RateSource.bcvUsd, this.manualRate});

  final RateSource rateSource;
  final double? manualRate;

  factory GymSettings.fromJson(Map<String, dynamic> j) => GymSettings(
        rateSource: RateSource.fromCode(j['rate_source'] as String?),
        manualRate: _num(j['manual_rate']),
      );

  Map<String, dynamic> toJson() => {'rate_source': rateSource.code, 'manual_rate': manualRate};
}

/// Tasa que aplica según los ajustes y las tasas consultadas. Null si no hay
/// (sin conexión y sin tasa manual).
ExchangeRate? effectiveRate(GymSettings settings, Map<RateSource, ExchangeRate> fetched) =>
    settings.rateSource == RateSource.manual
        ? (settings.manualRate == null ? null : ExchangeRate(RateSource.manual, settings.manualRate!))
        : fetched[settings.rateSource];

// ---------------------------------------------------------------------------
// Planes y clientes

class Plan {
  const Plan({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.durationDays,
    this.active = true,
  });

  final String id;
  final String name;
  final int priceCents;
  final int durationDays;
  final bool active;

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
        id: j['id'] as String,
        name: j['name'] as String,
        priceCents: j['price_cents'] as int,
        durationDays: j['duration_days'] as int,
        active: j['active'] as bool? ?? true,
      );
}

class PlanInput {
  const PlanInput({
    required this.name,
    required this.priceCents,
    required this.durationDays,
    this.active = true,
  });

  final String name;
  final int priceCents;
  final int durationDays;
  final bool active;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price_cents': priceCents,
        'duration_days': durationDays,
        'active': active,
      };
}

/// Cliente con su último vencimiento ya resuelto (vista `member_overview`).
/// La cédula se guarda como "V-24518330" y el teléfono solo con dígitos.
class Member {
  const Member({
    required this.id,
    required this.fullName,
    required this.createdAt,
    this.documentId,
    this.phone,
    this.email,
    this.notes,
    this.expiresOn,
    this.planName,
    this.photoPath,
    this.active = true,
  });

  final String id;
  final String fullName;
  final String? documentId;
  final String? phone;
  final String? email;
  final String? notes;
  final DateTime createdAt;
  final DateTime? expiresOn;
  final String? planName;
  final String? photoPath;
  final bool active;

  MembershipStatus status(DateTime today) => active ? membershipStatus(expiresOn, today) : MembershipStatus.inactive;

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return (parts.first[0] + (parts.length > 1 ? parts[1][0] : '')).toUpperCase();
  }

  /// Busca por nombre; si la búsqueda trae números, también por cédula y
  /// teléfono sin importar puntos o guiones ("24.518" encuentra V-24518330).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (fullName.toLowerCase().contains(q)) return true;
    final digits = onlyDigits(q);
    return digits.isNotEmpty && (onlyDigits(documentId).contains(digits) || onlyDigits(phone).contains(digits));
  }

  MemberInput toInput() => MemberInput(
        fullName: fullName,
        documentId: documentId,
        phone: phone,
        email: email,
        notes: notes,
      );

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id'] as String,
        fullName: j['full_name'] as String,
        documentId: j['document_id'] as String?,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        notes: j['notes'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        expiresOn: _date(j['expires_on']),
        planName: j['plan_name'] as String?,
        photoPath: j['photo_path'] as String?,
        active: j['active'] as bool? ?? true,
      );

  Member copyWith({DateTime? expiresOn, String? planName, MemberInput? input, String? Function()? photoPath, bool? active}) => Member(
        id: id,
        createdAt: createdAt,
        fullName: input?.fullName ?? fullName,
        documentId: input != null ? input.documentId : documentId,
        phone: input != null ? input.phone : phone,
        email: input != null ? input.email : email,
        notes: input != null ? input.notes : notes,
        expiresOn: expiresOn ?? this.expiresOn,
        planName: planName ?? this.planName,
        photoPath: photoPath != null ? photoPath() : this.photoPath,
        active: active ?? this.active,
      );
}

class MemberInput {
  const MemberInput({
    required this.fullName,
    this.documentId,
    this.phone,
    this.email,
    this.notes,
  });

  final String fullName;
  final String? documentId;
  final String? phone;
  final String? email;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'document_id': documentId,
        'phone': phone,
        'email': email,
        'notes': notes,
      };
}

// ---------------------------------------------------------------------------
// Pagos de membresía

class Payment {
  const Payment({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.planId,
    required this.planName,
    required this.amountCents,
    required this.methodCode,
    required this.methodName,
    required this.periodStart,
    required this.periodEnd,
    required this.paidAt,
    this.currency = Currency.usd,
    this.rate,
    this.rateSource,
    this.amountVesCents,
    this.voidedAt,
    this.voidReason,
  });

  final String id;
  final String memberId;
  final String memberName;
  final String planId;
  final String planName;

  /// Siempre en centavos de dólar (precio del plan).
  final int amountCents;
  final String methodCode;
  final String methodName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime paidAt;
  final Currency currency;
  final double? rate;
  final RateSource? rateSource;

  /// Lo que se cobró en bolívares (si el método es en Bs.).
  final int? amountVesCents;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get voided => voidedAt != null;

  /// Espera `members(full_name)`, `plans(name)` y `payment_methods(name)`.
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        id: j['id'] as String,
        memberId: j['member_id'] as String,
        memberName: (j['members'] as Map?)?['full_name'] as String? ?? '—',
        planId: j['plan_id'] as String,
        planName: (j['plans'] as Map?)?['name'] as String? ?? '—',
        amountCents: j['amount_cents'] as int,
        methodCode: j['method'] as String,
        methodName: (j['payment_methods'] as Map?)?['name'] as String? ?? j['method'] as String,
        periodStart: _date(j['period_start'])!,
        periodEnd: _date(j['period_end'])!,
        paidAt: _timestamp(j['paid_at'])!,
        currency: Currency.fromCode(j['currency'] as String?),
        rate: _num(j['rate']),
        rateSource: j['rate_source'] == null ? null : RateSource.fromCode(j['rate_source'] as String),
        amountVesCents: _int(j['amount_ves_cents']),
        voidedAt: _timestamp(j['voided_at']),
        voidReason: j['void_reason'] as String?,
      );

  Payment voidedWith(String reason, DateTime at) => Payment(
        id: id,
        memberId: memberId,
        memberName: memberName,
        planId: planId,
        planName: planName,
        amountCents: amountCents,
        methodCode: methodCode,
        methodName: methodName,
        periodStart: periodStart,
        periodEnd: periodEnd,
        paidAt: paidAt,
        currency: currency,
        rate: rate,
        rateSource: rateSource,
        amountVesCents: amountVesCents,
        voidedAt: at,
        voidReason: reason,
      );
}

/// Cobro de membresía a registrar. El periodo calculado aquí es la vista
/// previa; en Supabase lo vuelve a calcular `register_payment` con la misma
/// regla dentro de una transacción (fuente de verdad ante cobros simultáneos).
class NewPayment {
  const NewPayment({
    required this.member,
    required this.plan,
    required this.method,
    required this.today,
    required this.periodStart,
    required this.periodEnd,
    this.rate,
  });

  factory NewPayment.renewal({
    required Member member,
    required Plan plan,
    required PaymentMethod method,
    required DateTime today,
    ExchangeRate? rate,
  }) {
    final period = renewalPeriod(
      currentExpiresOn: member.expiresOn,
      today: today,
      durationDays: plan.durationDays,
    );
    return NewPayment(
      member: member,
      plan: plan,
      method: method,
      today: today,
      periodStart: period.start,
      periodEnd: period.end,
      rate: method.inBolivares ? rate : null,
    );
  }

  final Member member;
  final Plan plan;
  final PaymentMethod method;

  /// Fecha local de la recepción (el servidor trabaja en UTC).
  final DateTime today;
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Tasa usada si el método es en bolívares.
  final ExchangeRate? rate;

  int get amountCents => plan.priceCents;
  int? get amountVesCents => rate?.vesCents(amountCents);

  /// Un cobro en Bs. sin tasa no se puede registrar.
  bool get ready => !method.inBolivares || rate != null;
}

// ---------------------------------------------------------------------------
// Asistencia

enum CheckInMethod { manual, huella, qr }

class Attendance {
  const Attendance({
    required this.id,
    required this.memberId,
    required this.memberName,
    required this.checkedInAt,
    this.method = CheckInMethod.manual,
  });

  final String id;
  final String memberId;
  final String memberName;
  final DateTime checkedInAt;
  final CheckInMethod method;

  factory Attendance.fromJson(Map<String, dynamic> j) => Attendance(
        id: j['id'] as String,
        memberId: j['member_id'] as String,
        memberName: (j['members'] as Map?)?['full_name'] as String? ?? '—',
        checkedInAt: DateTime.parse(j['checked_in_at'] as String).toLocal(),
        method: CheckInMethod.values.byName(j['method'] as String),
      );
}

// ---------------------------------------------------------------------------
// Tienda: proveedores, productos, ventas

class Supplier {
  const Supplier({required this.id, required this.name, this.phone, this.email, this.notes});

  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? notes;

  factory Supplier.fromJson(Map<String, dynamic> j) => Supplier(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        notes: j['notes'] as String?,
      );
}

class SupplierInput {
  const SupplierInput({required this.name, this.phone, this.email, this.notes});

  final String name;
  final String? phone;
  final String? email;
  final String? notes;

  Map<String, dynamic> toJson() => {'name': name, 'phone': phone, 'email': email, 'notes': notes};
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.priceCents,
    required this.costCents,
    required this.stock,
    this.minStock = 0,
    this.sku,
    this.supplierId,
    this.supplierName,
    this.active = true,
  });

  final String id;
  final String name;
  final String? sku;
  final int priceCents;
  final int costCents;

  /// Stock actual = inicial ± ajustes + compras − ventas (sin anuladas).
  final int stock;
  final int minStock;
  final String? supplierId;
  final String? supplierName;
  final bool active;

  bool get lowStock => stock <= minStock;

  /// Espera la relación embebida `suppliers(name)`.
  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        sku: j['sku'] as String?,
        priceCents: j['price_cents'] as int,
        costCents: j['cost_cents'] as int,
        stock: j['stock'] as int,
        minStock: j['min_stock'] as int,
        supplierId: j['supplier_id'] as String?,
        supplierName: (j['suppliers'] as Map?)?['name'] as String?,
        active: j['active'] as bool,
      );

  Product withStock(int stock, {int? costCents}) => Product(
        id: id,
        name: name,
        sku: sku,
        priceCents: priceCents,
        costCents: costCents ?? this.costCents,
        stock: stock,
        minStock: minStock,
        supplierId: supplierId,
        supplierName: supplierName,
        active: active,
      );
}

/// Datos editables de un producto. El stock no está aquí: solo cambia con
/// compras, ventas y ajustes, para que quede registro.
class ProductInput {
  const ProductInput({
    required this.name,
    required this.priceCents,
    required this.costCents,
    this.minStock = 0,
    this.sku,
    this.supplierId,
    this.active = true,
  });

  final String name;
  final String? sku;
  final int priceCents;
  final int costCents;
  final int minStock;
  final String? supplierId;
  final bool active;

  Map<String, dynamic> toJson() => {
        'name': name,
        'sku': sku,
        'price_cents': priceCents,
        'cost_cents': costCents,
        'min_stock': minStock,
        'supplier_id': supplierId,
        'active': active,
      };
}

class CartLine {
  const CartLine(this.product, this.quantity);

  final Product product;
  final int quantity;

  int get totalCents => product.priceCents * quantity;
}

int cartTotal(Iterable<CartLine> lines) => lines.fold(0, (s, l) => s + l.totalCents);

class SaleItem {
  const SaleItem({required this.productId, required this.productName, required this.quantity, required this.unitPriceCents});

  final String productId;
  final String productName;
  final int quantity;
  final int unitPriceCents;

  int get totalCents => quantity * unitPriceCents;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        productId: j['product_id'] as String,
        productName: (j['products'] as Map?)?['name'] as String? ?? '—',
        quantity: j['quantity'] as int,
        unitPriceCents: j['unit_price_cents'] as int,
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.methodCode,
    required this.methodName,
    required this.totalCents,
    required this.soldAt,
    required this.items,
    this.memberId,
    this.memberName,
    this.currency = Currency.usd,
    this.rate,
    this.rateSource,
    this.totalVesCents,
    this.voidedAt,
    this.voidReason,
  });

  final String id;
  final String? memberId;
  final String? memberName;
  final String methodCode;
  final String methodName;
  final int totalCents;
  final DateTime soldAt;
  final List<SaleItem> items;
  final Currency currency;
  final double? rate;
  final RateSource? rateSource;
  final int? totalVesCents;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get voided => voidedAt != null;

  String get description => items.map((i) => i.quantity == 1 ? i.productName : '${i.quantity}× ${i.productName}').join(', ');

  /// Espera `members(full_name)`, `payment_methods(name)` y
  /// `sale_items(*, products(name))`.
  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] as String,
        memberId: j['member_id'] as String?,
        memberName: (j['members'] as Map?)?['full_name'] as String?,
        methodCode: j['method'] as String,
        methodName: (j['payment_methods'] as Map?)?['name'] as String? ?? j['method'] as String,
        totalCents: j['total_cents'] as int,
        soldAt: _timestamp(j['sold_at'])!,
        items: [for (final i in (j['sale_items'] as List? ?? const [])) SaleItem.fromJson(i as Map<String, dynamic>)],
        currency: Currency.fromCode(j['currency'] as String?),
        rate: _num(j['rate']),
        rateSource: j['rate_source'] == null ? null : RateSource.fromCode(j['rate_source'] as String),
        totalVesCents: _int(j['total_ves_cents']),
        voidedAt: _timestamp(j['voided_at']),
        voidReason: j['void_reason'] as String?,
      );

  Sale voidedWith(String reason, DateTime at) => Sale(
        id: id,
        memberId: memberId,
        memberName: memberName,
        methodCode: methodCode,
        methodName: methodName,
        totalCents: totalCents,
        soldAt: soldAt,
        items: items,
        currency: currency,
        rate: rate,
        rateSource: rateSource,
        totalVesCents: totalVesCents,
        voidedAt: at,
        voidReason: reason,
      );
}

// ---------------------------------------------------------------------------
// Compras: alimentan el inventario

class PurchaseItem {
  const PurchaseItem({required this.productId, required this.productName, required this.quantity, required this.unitCostCents});

  final String productId;
  final String productName;
  final int quantity;
  final int unitCostCents;

  int get totalCents => quantity * unitCostCents;

  factory PurchaseItem.fromJson(Map<String, dynamic> j) => PurchaseItem(
        productId: j['product_id'] as String,
        productName: (j['products'] as Map?)?['name'] as String? ?? '—',
        quantity: j['quantity'] as int,
        unitCostCents: j['unit_cost_cents'] as int,
      );
}

class Purchase {
  const Purchase({
    required this.id,
    required this.purchasedOn,
    required this.totalCents,
    required this.items,
    required this.createdAt,
    this.supplierId,
    this.supplierName,
    this.invoice,
    this.notes,
    this.voidedAt,
    this.voidReason,
  });

  final String id;
  final String? supplierId;
  final String? supplierName;
  final String? invoice;
  final DateTime purchasedOn;
  final String? notes;
  final int totalCents;
  final List<PurchaseItem> items;
  final DateTime createdAt;
  final DateTime? voidedAt;
  final String? voidReason;

  bool get voided => voidedAt != null;
  int get units => items.fold(0, (s, i) => s + i.quantity);

  /// Espera `suppliers(name)` y `purchase_items(*, products(name))`.
  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        id: j['id'] as String,
        supplierId: j['supplier_id'] as String?,
        supplierName: (j['suppliers'] as Map?)?['name'] as String?,
        invoice: j['invoice'] as String?,
        purchasedOn: _date(j['purchased_on'])!,
        notes: j['notes'] as String?,
        totalCents: j['total_cents'] as int,
        items: [for (final i in (j['purchase_items'] as List? ?? const [])) PurchaseItem.fromJson(i as Map<String, dynamic>)],
        createdAt: _timestamp(j['created_at'])!,
        voidedAt: _timestamp(j['voided_at']),
        voidReason: j['void_reason'] as String?,
      );

  Purchase voidedWith(String reason, DateTime at) => Purchase(
        id: id,
        supplierId: supplierId,
        supplierName: supplierName,
        invoice: invoice,
        purchasedOn: purchasedOn,
        notes: notes,
        totalCents: totalCents,
        items: items,
        createdAt: createdAt,
        voidedAt: at,
        voidReason: reason,
      );
}

class PurchaseLine {
  const PurchaseLine({required this.product, required this.quantity, required this.unitCostCents});

  final Product product;
  final int quantity;
  final int unitCostCents;

  int get totalCents => quantity * unitCostCents;
}

class NewPurchase {
  const NewPurchase({required this.lines, required this.purchasedOn, this.supplierId, this.invoice, this.notes});

  final List<PurchaseLine> lines;
  final DateTime purchasedOn;
  final String? supplierId;
  final String? invoice;
  final String? notes;

  int get totalCents => lines.fold(0, (s, l) => s + l.totalCents);
}

// ---------------------------------------------------------------------------
// Caja

/// Lo cobrado con un método en el día: equivalente en dólares y, si es en
/// bolívares, lo que efectivamente entró en Bs.
class MethodTotal {
  const MethodTotal({required this.name, required this.currency, this.usdCents = 0, this.vesCents = 0, this.count = 0});

  final String name;
  final Currency currency;
  final int usdCents;
  final int vesCents;
  final int count;

  MethodTotal add(int usd, int? ves) =>
      MethodTotal(name: name, currency: currency, usdCents: usdCents + usd, vesCents: vesCents + (ves ?? 0), count: count + 1);
}

/// Cierre de caja: suma lo cobrado (membresías + tienda) sin contar anulaciones.
class CashSummary {
  CashSummary._(this.membershipCents, this.storeCents, this.byMethod, this.voidedCount, this.voidedCents);

  factory CashSummary.of(Iterable<Payment> payments, Iterable<Sale> sales) {
    var membership = 0, store = 0, voidedCount = 0, voidedCents = 0;
    final byMethod = <String, MethodTotal>{};
    for (final (usd, ves, code, name, currency, voided, isStore) in [
      for (final p in payments) (p.amountCents, p.amountVesCents, p.methodCode, p.methodName, p.currency, p.voided, false),
      for (final s in sales) (s.totalCents, s.totalVesCents, s.methodCode, s.methodName, s.currency, s.voided, true),
    ]) {
      if (voided) {
        voidedCount++;
        voidedCents += usd;
        continue;
      }
      byMethod[code] = (byMethod[code] ?? MethodTotal(name: name, currency: currency)).add(usd, ves);
      if (isStore) {
        store += usd;
      } else {
        membership += usd;
      }
    }
    return CashSummary._(membership, store, byMethod, voidedCount, voidedCents);
  }

  final int membershipCents;
  final int storeCents;
  final Map<String, MethodTotal> byMethod;
  final int voidedCount;
  final int voidedCents;

  /// Total en equivalente de dólares.
  int get totalCents => membershipCents + storeCents;

  /// Bolívares que efectivamente entraron (métodos en Bs.).
  int get totalVesCents => byMethod.values.fold(0, (s, m) => s + m.vesCents);
}
