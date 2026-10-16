// Hecho por Briann$ Workers Corp.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ImageProvider, NetworkImage;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/models.dart';
import '../domain/staff.dart';
import '../domain/workouts.dart';

/// Acceso a datos del gimnasio. Implementaciones: [SupabaseGymRepository]
/// (producción) y `DemoGymRepository` (sin backend, para demo y tests).
/// Los errores de negocio llegan como [GymException] o [PostgrestException];
/// usa [friendlyError] para mostrarlos.
abstract interface class GymRepository {
  Future<List<Member>> members();
  Future<Member> createMember(MemberInput input);
  Future<void> updateMember(String id, MemberInput input);
  Future<void> setMemberActive(String id, bool active);
  /// Lo saca de la planilla; sus pagos, ventas y asistencias se conservan.
  Future<void> deleteMember(Member member);

  /// Fotos de perfil listas para mostrar, por id de cliente.
  Future<Map<String, ImageProvider>> memberPhotos(List<Member> members);
  Future<void> setMemberPhoto(Member member, Uint8List bytes, {String mimeType = 'image/jpeg'});
  Future<void> removeMemberPhoto(Member member);

  Future<List<Plan>> plans();
  Future<void> savePlan(PlanInput input, {String? id});

  Future<List<PaymentMethod>> paymentMethods();
  Future<void> addPaymentMethod(String name, Currency currency);
  Future<void> setPaymentMethodActive(String code, bool active);

  Future<GymSettings> settings();
  Future<void> saveSettings(GymSettings settings);

  Future<List<Payment>> payments({String? memberId, DateTime? from, DateTime? to, int limit = 300});
  /// Devuelve el pago con el periodo definitivo calculado por el backend.
  Future<Payment> addPayment(NewPayment payment);
  Future<void> voidPayment(String id, String reason);

  Future<List<Attendance>> attendanceSince(DateTime from);
  Future<void> checkIn(String memberId, {CheckInMethod method = CheckInMethod.manual});

  Future<List<Supplier>> suppliers();
  Future<void> saveSupplier(SupplierInput input, {String? id});

  Future<List<Product>> products();
  /// Devuelve el id del producto (nuevo o existente).
  Future<String> saveProduct(ProductInput input, {String? id});
  /// Stock inicial o ajuste (cantidad > 0 suma, < 0 resta). Devuelve el nuevo stock.
  Future<int> addStock(String productId, int quantity, {int? unitCostCents, String? note});

  Future<List<Sale>> sales({DateTime? from, DateTime? to, int limit = 200});
  Future<String> registerSale(List<CartLine> lines, PaymentMethod method, {String? memberId, ExchangeRate? rate});
  Future<void> voidSale(String id, String reason);

  Future<List<Purchase>> purchases({DateTime? from, DateTime? to, int limit = 200});
  Future<String> registerPurchase(NewPurchase purchase);
  Future<void> voidPurchase(String id, String reason);

  // Entrenos
  Future<List<WorkoutLog>> workouts({String? memberId, DateTime? from, int limit = 300});
  Future<String> saveWorkout(WorkoutInput input, {String? id});
  Future<void> deleteWorkout(String id);

  // Personal y roles
  /// Quién tiene la sesión iniciada y qué puede hacer; null si la cuenta no
  /// está activa en el personal.
  Future<StaffAccess?> myAccess();
  Future<List<StaffMember>> staffDirectory();
  Future<String> createStaff(NewStaff staff);
  Future<void> updateStaff(String userId, StaffInput input);
  Future<void> setStaffStatus(String userId, StaffStatus status);
  Future<void> setStaffPassword(String userId, String password);
  Future<void> changeOwnPassword(String password);
  Future<List<PermissionInfo>> permissions();
  Future<Map<StaffRole, Set<String>>> rolePermissions();
  Future<void> setRolePermission(StaffRole role, String permission, bool enabled);
  Future<List<StaffShift>> shifts(String userId);
  Future<void> saveShifts(String userId, List<StaffShift> shifts);
  Future<List<StaffTimeEntry>> timeEntries({String? userId, required DateTime from});
  /// Marca entrada o salida de quien tiene la sesión. Devuelve la jornada.
  Future<StaffTimeEntry> clockInOut();
  Future<List<AuditEntry>> auditLog({int limit = 200});
}

String friendlyError(Object e) => switch (e) {
      PostgrestException(code: '23505') => 'Ya existe un registro con ese dato único (cédula o código).',
      PostgrestException(code: '42501', :final message) when message.startsWith('Tu rol') || message.startsWith('Solo') || message.startsWith('No puedes') =>
        message.startsWith('Tu rol') ? 'Tu rol no tiene permiso para esta acción.' : message,
      PostgrestException(code: '42501') => 'Tu usuario no tiene permiso para esta acción.',
      PostgrestException(code: '23514', :final message) when message.contains('dueño') => message,
      // Reglas de formato del servidor (cédula, teléfono, correo, largos).
      PostgrestException(code: '23514', :final message) => switch (message) {
          _ when message.contains('document') => 'La cédula debe ser V o E seguida de 6 a 9 dígitos.',
          _ when message.contains('phone') => 'El teléfono debe tener 10 u 11 dígitos.',
          _ when message.contains('email') => 'El correo no es válido.',
          _ => 'Algún dato no es válido o es demasiado largo.',
        },
      PostgrestException(:final message) => message,
      StorageException(:final message) => 'No se pudo guardar la foto: $message',
      AuthRetryableFetchException() => 'Sin conexión con el servidor. Revisa internet e intenta de nuevo.',
      AuthException(:final message) => message,
      // http.ClientException (web y móvil) y SocketException (móvil) = sin red.
      _ when '$e'.contains('ClientException') || '$e'.contains('SocketException') || '$e'.contains('Failed to fetch') =>
        'Sin conexión con el servidor. Revisa internet e intenta de nuevo.',
      _ => '$e',
    };

class SupabaseGymRepository implements GymRepository {
  SupabaseGymRepository(this._db);
  final SupabaseClient _db;

  static const _photoBucket = 'member-photos';
  static const _paymentSelect = '*, members(full_name), plans(name), payment_methods(name)';
  // Sin costos: products.cost_cents y sale_items.unit_cost_cents no se pueden
  // leer directo; los costos llegan por product_costs() solo con permiso.
  static const _saleSelect =
      '*, members(full_name), payment_methods(name), sale_items(id, sale_id, product_id, quantity, unit_price_cents, products(name))';
  static const _productSelect = 'id, name, sku, price_cents, stock, min_stock, supplier_id, active, suppliers(name)';
  static const _workoutSelect = '*, members(full_name)';
  static const _purchaseSelect = '*, suppliers(name), purchase_items(*, products(name))';

  @override
  Future<List<Member>> members() async {
    final rows = await _db.from('member_overview').select().order('full_name');
    return rows.map(Member.fromJson).toList();
  }

  @override
  Future<Member> createMember(MemberInput input) async {
    final row = await _db.from('members').insert(input.toJson()).select().single();
    return Member.fromJson(row);
  }

  @override
  Future<void> updateMember(String id, MemberInput input) =>
      _db.from('members').update(input.toJson()).eq('id', id);

  @override
  Future<void> setMemberActive(String id, bool active) =>
      _db.from('members').update({'active': active}).eq('id', id);

  @override
  Future<void> deleteMember(Member member) async {
    final photo = await _db.rpc<String?>('delete_member', params: {'p_member_id': member.id});
    // La foto ya no se muestra en ningún lado; si falla borrarla no es grave.
    if (photo != null) {
      try {
        await _db.storage.from(_photoBucket).remove([photo]);
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, ImageProvider>> memberPhotos(List<Member> members) async {
    final withPhoto = members.where((m) => m.photoPath != null).toList();
    if (withPhoto.isEmpty) return const {};
    // Bucket privado: URLs firmadas en una sola petición, válidas 1 hora.
    final results = await _db.storage.from(_photoBucket).createSignedUrlsResult([for (final m in withPhoto) m.photoPath!], 3600);
    final byPath = {for (final r in results) if (r is SignedUrlSuccess) r.path: r.signedUrl};
    return {
      for (final m in withPhoto)
        if (byPath[m.photoPath] case final url?) m.id: NetworkImage(url),
    };
  }

  @override
  Future<void> setMemberPhoto(Member member, Uint8List bytes, {String mimeType = 'image/jpeg'}) async {
    // Nombre nuevo en cada cambio: evita que el navegador muestre la foto vieja en caché.
    final ext = mimeType.endsWith('png') ? 'png' : (mimeType.endsWith('webp') ? 'webp' : 'jpg');
    final path = '${member.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';
    final bucket = _db.storage.from(_photoBucket);
    await bucket.uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mimeType, upsert: true));
    await _db.from('members').update({'photo_path': path}).eq('id', member.id);
    if (member.photoPath != null) await bucket.remove([member.photoPath!]);
  }

  @override
  Future<void> removeMemberPhoto(Member member) async {
    if (member.photoPath == null) return;
    await _db.from('members').update({'photo_path': null}).eq('id', member.id);
    await _db.storage.from(_photoBucket).remove([member.photoPath!]);
  }

  @override
  Future<List<Plan>> plans() async {
    final rows = await _db.from('plans').select().order('active', ascending: false).order('duration_days');
    return rows.map(Plan.fromJson).toList();
  }

  @override
  Future<void> savePlan(PlanInput input, {String? id}) => id == null
      ? _db.from('plans').insert(input.toJson())
      : _db.from('plans').update(input.toJson()).eq('id', id);

  @override
  Future<List<PaymentMethod>> paymentMethods() async {
    final rows = await _db.from('payment_methods').select().order('position').order('name');
    return rows.map(PaymentMethod.fromJson).toList();
  }

  @override
  Future<void> addPaymentMethod(String name, Currency currency) async {
    final existing = (await paymentMethods()).map((m) => m.code).toSet();
    final base = methodCodeFor(name);
    var code = base;
    for (var i = 2; existing.contains(code); i++) {
      code = '${base}_$i';
    }
    await _db.from('payment_methods').insert({
      'code': code,
      'name': name.trim(),
      'currency': currency.code,
      'position': existing.length + 1,
    });
  }

  @override
  Future<void> setPaymentMethodActive(String code, bool active) =>
      _db.from('payment_methods').update({'active': active}).eq('code', code);

  @override
  Future<GymSettings> settings() async {
    final row = await _db.from('settings').select().maybeSingle();
    return row == null ? const GymSettings() : GymSettings.fromJson(row);
  }

  @override
  Future<void> saveSettings(GymSettings settings) =>
      _db.from('settings').update({...settings.toJson(), 'updated_at': DateTime.now().toUtc().toIso8601String()}).eq('id', true);

  @override
  Future<List<Payment>> payments({String? memberId, DateTime? from, DateTime? to, int limit = 300}) async {
    var query = _db.from('payments').select(_paymentSelect);
    if (memberId != null) query = query.eq('member_id', memberId);
    if (from != null) query = query.gte('paid_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lt('paid_at', to.toUtc().toIso8601String());
    final rows = await query.order('paid_at', ascending: false).limit(limit);
    return rows.map(Payment.fromJson).toList();
  }

  @override
  Future<Payment> addPayment(NewPayment p) async {
    if (!p.ready) throw const GymException('Falta la tasa de cambio para cobrar en bolívares');
    final row = await _db.rpc<Map<String, dynamic>>('register_payment', params: {
      'p_member_id': p.member.id,
      'p_plan_id': p.plan.id,
      'p_method': p.method.code,
      'p_today': isoDate(p.today),
      'p_rate': p.rate?.value,
      'p_rate_source': p.rate?.source.code,
    });
    return Payment.fromJson({
      ...row,
      'members': {'full_name': p.member.fullName},
      'plans': {'name': p.plan.name},
      'payment_methods': {'name': p.method.name},
    });
  }

  @override
  Future<void> voidPayment(String id, String reason) =>
      _db.rpc<void>('void_payment', params: {'p_payment_id': id, 'p_reason': reason});

  @override
  Future<List<Attendance>> attendanceSince(DateTime from) async {
    final rows = await _db
        .from('attendance')
        .select('*, members(full_name)')
        .gte('checked_in_at', from.toUtc().toIso8601String())
        .order('checked_in_at', ascending: false);
    return rows.map(Attendance.fromJson).toList();
  }

  @override
  Future<void> checkIn(String memberId, {CheckInMethod method = CheckInMethod.manual}) =>
      _db.from('attendance').insert({'member_id': memberId, 'method': method.name});

  @override
  Future<List<Supplier>> suppliers() async {
    final rows = await _db.from('suppliers').select().order('name');
    return rows.map(Supplier.fromJson).toList();
  }

  @override
  Future<void> saveSupplier(SupplierInput input, {String? id}) => id == null
      ? _db.from('suppliers').insert(input.toJson())
      : _db.from('suppliers').update(input.toJson()).eq('id', id);

  @override
  Future<List<Product>> products() async {
    final rowsF = _db.from('products').select(_productSelect).order('active', ascending: false).order('name');
    final costsF = _db.rpc<List<dynamic>>('product_costs');
    final rows = await rowsF;
    final costs = {for (final c in await costsF) (c as Map)['product_id'] as String: c['cost_cents'] as int};
    return [for (final r in rows) Product.fromJson({...r, 'cost_cents': costs[r['id']]})];
  }

  @override
  Future<String> saveProduct(ProductInput input, {String? id}) async {
    if (id != null) {
      await _db.from('products').update(input.toJson()).eq('id', id);
      return id;
    }
    final row = await _db.from('products').insert(input.toJson()).select('id').single();
    return row['id'] as String;
  }

  @override
  Future<int> addStock(String productId, int quantity, {int? unitCostCents, String? note}) =>
      _db.rpc<int>('add_stock', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_unit_cost_cents': unitCostCents,
        'p_note': note,
      });

  @override
  Future<List<Sale>> sales({DateTime? from, DateTime? to, int limit = 200}) async {
    var query = _db.from('sales').select(_saleSelect);
    if (from != null) query = query.gte('sold_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lt('sold_at', to.toUtc().toIso8601String());
    final rows = await query.order('sold_at', ascending: false).limit(limit);
    return rows.map(Sale.fromJson).toList();
  }

  @override
  Future<String> registerSale(List<CartLine> lines, PaymentMethod method, {String? memberId, ExchangeRate? rate}) {
    if (method.inBolivares && rate == null) throw const GymException('Falta la tasa de cambio para cobrar en bolívares');
    return _db.rpc<String>('register_sale', params: {
      'p_items': [for (final l in lines) {'product_id': l.product.id, 'quantity': l.quantity}],
      'p_method': method.code,
      'p_member_id': memberId,
      'p_rate': method.inBolivares ? rate!.value : null,
      'p_rate_source': method.inBolivares ? rate!.source.code : null,
    });
  }

  @override
  Future<void> voidSale(String id, String reason) =>
      _db.rpc<void>('void_sale', params: {'p_sale_id': id, 'p_reason': reason});

  @override
  Future<List<Purchase>> purchases({DateTime? from, DateTime? to, int limit = 200}) async {
    var query = _db.from('purchases').select(_purchaseSelect);
    if (from != null) query = query.gte('purchased_on', isoDate(from));
    if (to != null) query = query.lt('purchased_on', isoDate(to));
    final rows = await query.order('purchased_on', ascending: false).order('created_at', ascending: false).limit(limit);
    return rows.map(Purchase.fromJson).toList();
  }

  @override
  Future<String> registerPurchase(NewPurchase p) => _db.rpc<String>('register_purchase', params: {
        'p_items': [
          for (final l in p.lines) {'product_id': l.product.id, 'quantity': l.quantity, 'unit_cost_cents': l.unitCostCents},
        ],
        'p_supplier_id': p.supplierId,
        'p_invoice': p.invoice,
        'p_purchased_on': isoDate(p.purchasedOn),
        'p_notes': p.notes,
      });

  @override
  Future<void> voidPurchase(String id, String reason) =>
      _db.rpc<void>('void_purchase', params: {'p_purchase_id': id, 'p_reason': reason});

  // -------------------------------------------------------------------------
  // Entrenos

  @override
  Future<List<WorkoutLog>> workouts({String? memberId, DateTime? from, int limit = 300}) async {
    var query = _db.from('workout_logs').select(_workoutSelect);
    if (memberId != null) query = query.eq('member_id', memberId);
    if (from != null) query = query.gte('trained_on', isoDate(from));
    final rows = await query.order('trained_on', ascending: false).order('created_at', ascending: false).limit(limit);
    return rows.map(WorkoutLog.fromJson).toList();
  }

  @override
  Future<String> saveWorkout(WorkoutInput input, {String? id}) async {
    if (id != null) {
      await _db.from('workout_logs').update(input.toJson()).eq('id', id);
      return id;
    }
    final row = await _db.from('workout_logs').insert(input.toJson()).select('id').single();
    return row['id'] as String;
  }

  @override
  Future<void> deleteWorkout(String id) async {
    final rows = await _db.from('workout_logs').delete().eq('id', id).select('id');
    if (rows.isEmpty) throw const GymException('Solo puedes borrar los entrenos que registraste tú');
  }

  // -------------------------------------------------------------------------
  // Personal y roles

  @override
  Future<StaffAccess?> myAccess() async {
    if (_db.auth.currentUser == null) return null;
    final rows = await _db.rpc<List<dynamic>>('my_access');
    return rows.isEmpty ? null : StaffAccess.fromJson(rows.first as Map<String, dynamic>);
  }

  @override
  Future<List<StaffMember>> staffDirectory() async {
    final rows = await _db.rpc<List<dynamic>>('staff_directory');
    return [for (final r in rows) StaffMember.fromJson(r as Map<String, dynamic>)];
  }

  /// La Edge Function `staff-admin` crea la cuenta con la clave de servicio.
  Future<Map<String, dynamic>> _staffAdmin(Map<String, dynamic> body) async {
    try {
      final res = await _db.functions.invoke('staff-admin', body: body);
      return Map<String, dynamic>.from(res.data as Map);
    } on FunctionException catch (e) {
      final details = e.details;
      final msg = details is Map ? details['error'] as String? : null;
      if (e.status == 0) throw const GymException('Sin conexión con el servidor. Revisa internet e intenta de nuevo.');
      throw GymException(msg ?? 'No se pudo completar (${e.status})');
    }
  }

  @override
  Future<String> createStaff(NewStaff s) async {
    final res = await _staffAdmin({
      'action': 'create',
      'email': s.email,
      'password': s.password,
      'full_name': s.input.fullName,
      'role': s.input.role.code,
      'document_id': s.input.documentId,
      'phone': s.input.phone,
      'hired_on': s.input.hiredOn == null ? null : isoDate(s.input.hiredOn!),
      'notes': s.input.notes,
    });
    return res['user_id'] as String;
  }

  @override
  Future<void> updateStaff(String userId, StaffInput i) => _db.rpc<void>('staff_update', params: {
        'p_user_id': userId,
        'p_full_name': i.fullName,
        'p_role': i.role.code,
        'p_document_id': i.documentId,
        'p_phone': i.phone,
        'p_email': i.email,
        'p_hired_on': i.hiredOn == null ? null : isoDate(i.hiredOn!),
        'p_notes': i.notes,
      });

  @override
  Future<void> setStaffStatus(String userId, StaffStatus status) =>
      _db.rpc<void>('staff_set_status', params: {'p_user_id': userId, 'p_status': status.code});

  @override
  Future<void> setStaffPassword(String userId, String password) =>
      _staffAdmin({'action': 'set_password', 'user_id': userId, 'password': password});

  @override
  Future<void> changeOwnPassword(String password) => _db.auth.updateUser(UserAttributes(password: password));

  @override
  Future<List<PermissionInfo>> permissions() async {
    final rows = await _db.from('permissions').select().order('position');
    return rows.map(PermissionInfo.fromJson).toList();
  }

  @override
  Future<Map<StaffRole, Set<String>>> rolePermissions() async {
    final rows = await _db.from('role_permissions').select();
    final map = {for (final r in StaffRole.editable) r: <String>{}};
    for (final r in rows) {
      map[StaffRole.fromCode(r['role'] as String)]?.add(r['permission'] as String);
    }
    return map;
  }

  @override
  Future<void> setRolePermission(StaffRole role, String permission, bool enabled) => _db.rpc<void>(
        'set_role_permission',
        params: {'p_role': role.code, 'p_permission': permission, 'p_enabled': enabled},
      );

  @override
  Future<List<StaffShift>> shifts(String userId) async {
    final rows = await _db.from('staff_shifts').select().eq('user_id', userId).order('weekday');
    return rows.map(StaffShift.fromJson).toList();
  }

  @override
  Future<void> saveShifts(String userId, List<StaffShift> shifts) async {
    await _db.from('staff_shifts').delete().eq('user_id', userId);
    if (shifts.isNotEmpty) await _db.from('staff_shifts').insert([for (final s in shifts) s.toJson(userId)]);
  }

  @override
  Future<List<StaffTimeEntry>> timeEntries({String? userId, required DateTime from}) async {
    var q = _db.from('staff_time_entries').select().gte('clock_in', from.toUtc().toIso8601String());
    if (userId != null) q = q.eq('user_id', userId);
    final rows = await q.order('clock_in', ascending: false).limit(500);
    return rows.map(StaffTimeEntry.fromJson).toList();
  }

  @override
  Future<StaffTimeEntry> clockInOut() async {
    final row = await _db.rpc<Map<String, dynamic>>('staff_clock');
    return StaffTimeEntry.fromJson(row);
  }

  @override
  Future<List<AuditEntry>> auditLog({int limit = 200}) async {
    final rows = await _db.from('audit_log').select().order('at', ascending: false).limit(limit);
    final staff = await _db.from('staff').select('user_id, full_name');
    final names = {for (final s in staff) s['user_id'] as String: s['full_name'] as String};
    return [for (final r in rows) AuditEntry.fromJson(r, names)];
  }
}

// ---------------------------------------------------------------------------
// Providers

/// Se sobrescribe en `main` con la implementación real o la demo.
final gymRepositoryProvider = Provider<GymRepository>(
  (ref) => throw UnimplementedError('gymRepositoryProvider sin configurar'),
);

/// Cliente de Supabase, o null en modo demo (sin login).
final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final _authChangesProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider)?.auth.onAuthStateChange ?? const Stream.empty(),
);

/// Quién tiene la sesión iniciada, su rol y sus permisos. null = la cuenta no
/// está activa en el personal (RLS no le deja ver nada). En modo demo es la
/// persona elegida en el selector de rol.
final currentStaffProvider = FutureProvider<StaffAccess?>((ref) async {
  ref.watch(_authChangesProvider); // se recalcula al iniciar/cerrar sesión
  return ref.watch(gymRepositoryProvider).myAccess();
});

/// ¿Puede la sesión actual hacer [permission]? false mientras carga.
final canProvider = Provider.family<bool, String>(
  (ref, permission) => ref.watch(currentStaffProvider).value?.can(permission) ?? false,
);

final staffDirectoryProvider = FutureProvider<List<StaffMember>>(
  (ref) => ref.watch(gymRepositoryProvider).staffDirectory(),
);

final permissionCatalogProvider = FutureProvider<List<PermissionInfo>>(
  (ref) => ref.watch(gymRepositoryProvider).permissions(),
);

final rolePermissionsProvider = FutureProvider<Map<StaffRole, Set<String>>>(
  (ref) => ref.watch(gymRepositoryProvider).rolePermissions(),
);

final staffShiftsProvider = FutureProvider.family<List<StaffShift>, String>(
  (ref, userId) => ref.watch(gymRepositoryProvider).shifts(userId),
);

/// Jornadas de los últimos 62 días (todo el personal si se puede ver; si no,
/// solo las propias: RLS filtra).
final staffTimeEntriesProvider = FutureProvider<List<StaffTimeEntry>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(gymRepositoryProvider).timeEntries(from: DateTime(now.year, now.month - 1, 1));
});

/// Jornada abierta de quien tiene la sesión (null = fuera de turno).
final myOpenShiftProvider = FutureProvider<StaffTimeEntry?>((ref) async {
  final me = await ref.watch(currentStaffProvider.future);
  if (me == null) return null;
  final entries = await ref.watch(staffTimeEntriesProvider.future);
  return entries.where((e) => e.userId == me.userId && e.open).firstOrNull;
});

final auditLogProvider = FutureProvider<List<AuditEntry>>(
  (ref) => ref.watch(gymRepositoryProvider).auditLog(),
);

/// Reloj inyectable para que los tests sean deterministas.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final membersProvider = FutureProvider<List<Member>>(
  (ref) => ref.watch(gymRepositoryProvider).members(),
);

/// Fotos de perfil. Las URLs firmadas duran 1 h: se renuevan a los 50 min.
final memberPhotosProvider = FutureProvider<Map<String, ImageProvider>>((ref) async {
  final members = await ref.watch(membersProvider.future);
  final timer = Timer(const Duration(minutes: 50), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(gymRepositoryProvider).memberPhotos(members);
});

final plansProvider = FutureProvider<List<Plan>>(
  (ref) => ref.watch(gymRepositoryProvider).plans(),
);

/// Todos los métodos (activos e inactivos), en orden.
final paymentMethodsProvider = FutureProvider<List<PaymentMethod>>(
  (ref) => ref.watch(gymRepositoryProvider).paymentMethods(),
);

final settingsProvider = FutureProvider<GymSettings>(
  (ref) => ref.watch(gymRepositoryProvider).settings(),
);

final paymentsProvider = FutureProvider<List<Payment>>(
  (ref) => ref.watch(gymRepositoryProvider).payments(),
);

final memberPaymentsProvider = FutureProvider.family<List<Payment>, String>(
  (ref, memberId) => ref.watch(gymRepositoryProvider).payments(memberId: memberId),
);

final todayAttendanceProvider = FutureProvider<List<Attendance>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(gymRepositoryProvider).attendanceSince(DateTime(now.year, now.month, now.day));
});

final suppliersProvider = FutureProvider<List<Supplier>>(
  (ref) => ref.watch(gymRepositoryProvider).suppliers(),
);

final productsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(gymRepositoryProvider).products(),
);

final salesProvider = FutureProvider<List<Sale>>(
  (ref) => ref.watch(gymRepositoryProvider).sales(),
);

final purchasesProvider = FutureProvider<List<Purchase>>(
  (ref) => ref.watch(gymRepositoryProvider).purchases(),
);

/// Entrenos de los últimos 120 días (la pantalla filtra por cliente).
final workoutsProvider = FutureProvider<List<WorkoutLog>>((ref) {
  final now = ref.watch(clockProvider)();
  return ref.watch(gymRepositoryProvider).workouts(from: DateTime(now.year, now.month, now.day - 120));
});

/// Movimientos de un día (fecha local, a medianoche) para el cierre de caja.
final cashDayProvider = FutureProvider.family<(List<Payment>, List<Sale>), DateTime>((ref, day) async {
  final repo = ref.watch(gymRepositoryProvider);
  final to = DateTime(day.year, day.month, day.day + 1);
  final (payments, sales) = await (repo.payments(from: day, to: to), repo.sales(from: day, to: to)).wait;
  return (payments, sales);
});

/// Recarga todo lo que depende de datos tras una escritura.
void refreshGymData(WidgetRef ref) {
  ref
    ..invalidate(membersProvider)
    ..invalidate(memberPhotosProvider)
    ..invalidate(plansProvider)
    ..invalidate(paymentMethodsProvider)
    ..invalidate(settingsProvider)
    ..invalidate(paymentsProvider)
    ..invalidate(memberPaymentsProvider)
    ..invalidate(todayAttendanceProvider)
    ..invalidate(suppliersProvider)
    ..invalidate(productsProvider)
    ..invalidate(salesProvider)
    ..invalidate(purchasesProvider)
    ..invalidate(cashDayProvider)
    ..invalidate(workoutsProvider)
    ..invalidate(currentStaffProvider)
    ..invalidate(staffDirectoryProvider)
    ..invalidate(rolePermissionsProvider)
    ..invalidate(staffShiftsProvider)
    ..invalidate(staffTimeEntriesProvider)
    ..invalidate(auditLogProvider);
}
