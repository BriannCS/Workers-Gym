// Hecho por Briann$ - Workers Corp.
/// Personal, roles y permisos. Los permisos se comprueban en el servidor
/// (RLS y triggers en Supabase); la app los usa para mostrar solo lo que cada
/// rol puede hacer. Ver docs/control_de_personal.md.
library;

/// Códigos de permiso: los mismos que la tabla `public.permissions`.
abstract final class Perm {
  static const dashboardMoney = 'dashboard.money';
  static const attendanceCreate = 'attendance.create';
  static const membersView = 'members.view';
  static const membersEdit = 'members.edit';
  static const membersDelete = 'members.delete';
  static const paymentsView = 'payments.view';
  static const paymentsCreate = 'payments.create';
  static const paymentsVoid = 'payments.void';
  static const storeSell = 'store.sell';
  static const salesVoid = 'sales.void';
  static const inventoryView = 'inventory.view';
  static const inventoryManage = 'inventory.manage';
  static const cashOwn = 'cash.own';
  static const cashAll = 'cash.all';
  static const plansManage = 'plans.manage';
  static const settingsManage = 'settings.manage';
  static const staffView = 'staff.view';
  static const staffManage = 'staff.manage';
  static const rolesManage = 'roles.manage';
  static const auditView = 'audit.view';
}

/// Una fila del catálogo de permisos (para la matriz de roles).
class PermissionInfo {
  const PermissionInfo(this.code, this.label, this.module);

  final String code;
  final String label;
  final String module;

  factory PermissionInfo.fromJson(Map<String, dynamic> j) =>
      PermissionInfo(j['code'] as String, j['label'] as String, j['module'] as String);
}

/// Catálogo en el mismo orden que la base de datos. Lo usa el modo demo y
/// sirve de respaldo si la tabla no responde.
const permissionCatalog = <PermissionInfo>[
  PermissionInfo(Perm.dashboardMoney, 'Ver montos en Inicio', 'Inicio'),
  PermissionInfo(Perm.attendanceCreate, 'Registrar entradas de clientes', 'Asistencia'),
  PermissionInfo(Perm.membersView, 'Ver clientes', 'Clientes'),
  PermissionInfo(Perm.membersEdit, 'Crear y editar clientes', 'Clientes'),
  PermissionInfo(Perm.membersDelete, 'Desactivar y eliminar clientes', 'Clientes'),
  PermissionInfo(Perm.paymentsView, 'Ver pagos e historial de cobros', 'Pagos'),
  PermissionInfo(Perm.paymentsCreate, 'Cobrar membresías', 'Pagos'),
  PermissionInfo(Perm.paymentsVoid, 'Anular pagos', 'Pagos'),
  PermissionInfo(Perm.storeSell, 'Vender en la tienda', 'Tienda'),
  PermissionInfo(Perm.salesVoid, 'Anular ventas', 'Tienda'),
  PermissionInfo(Perm.inventoryView, 'Ver inventario y compras', 'Inventario'),
  PermissionInfo(Perm.inventoryManage, 'Productos, proveedores, compras y stock', 'Inventario'),
  PermissionInfo(Perm.cashOwn, 'Ver su propia caja', 'Caja'),
  PermissionInfo(Perm.cashAll, 'Ver la caja de todos y el cierre Z', 'Caja'),
  PermissionInfo(Perm.plansManage, 'Crear y editar planes y precios', 'Planes'),
  PermissionInfo(Perm.settingsManage, 'Tasa de cambio y métodos de pago', 'Ajustes'),
  PermissionInfo(Perm.staffView, 'Ver al personal', 'Personal'),
  PermissionInfo(Perm.staffManage, 'Crear, editar y suspender personal', 'Personal'),
  PermissionInfo(Perm.rolesManage, 'Cambiar los permisos de cada rol', 'Personal'),
  PermissionInfo(Perm.auditView, 'Ver la bitácora de actividad', 'Personal'),
];

/// Permisos con que nace cada rol (igual que la migración). El dueño los
/// tiene todos siempre.
final defaultRolePermissions = <StaffRole, Set<String>>{
  StaffRole.admin: {
    for (final p in permissionCatalog)
      if (p.code != Perm.rolesManage) p.code,
  },
  StaffRole.reception: {
    Perm.dashboardMoney,
    Perm.attendanceCreate,
    Perm.membersView,
    Perm.membersEdit,
    Perm.paymentsView,
    Perm.paymentsCreate,
    Perm.storeSell,
    Perm.inventoryView,
    Perm.cashOwn,
  },
  StaffRole.trainer: {Perm.attendanceCreate, Perm.membersView},
};

enum StaffRole {
  owner('owner', 'Dueño', 'Todo. Gestiona personal, roles y ajustes críticos.'),
  admin('admin', 'Administrador', 'Todo lo operativo y los reportes. Gestiona al personal, salvo a los dueños.'),
  reception('reception', 'Recepción', 'Asistencia, clientes, cobros, tienda y su propia caja.'),
  trainer('trainer', 'Entrenador', 'Asistencia y consulta de clientes, sin datos de pago.');

  const StaffRole(this.code, this.label, this.summary);
  final String code;
  final String label;
  final String summary;

  /// Roles cuyos permisos se pueden editar (el dueño siempre lo puede todo).
  static const editable = [admin, reception, trainer];

  static StaffRole fromCode(String? code) => values.firstWhere((r) => r.code == code, orElse: () => reception);
}

enum StaffStatus {
  active('active', 'Activo'),
  suspended('suspended', 'Suspendido'),
  terminated('terminated', 'De baja');

  const StaffStatus(this.code, this.label);
  final String code;
  final String label;

  static StaffStatus fromCode(String? code) => values.firstWhere((s) => s.code == code, orElse: () => active);
}

/// Quién tiene la sesión iniciada y qué puede hacer.
class StaffAccess {
  const StaffAccess({required this.userId, required this.fullName, required this.role, required this.permissions});

  final String userId;
  final String fullName;
  final StaffRole role;
  final Set<String> permissions;

  bool can(String permission) => role == StaffRole.owner || permissions.contains(permission);
  bool canAny(Iterable<String> any) => any.isEmpty || any.any(can);

  String get firstName => fullName.split(' ').first;

  factory StaffAccess.fromJson(Map<String, dynamic> j) => StaffAccess(
    userId: j['user_id'] as String,
    fullName: j['full_name'] as String,
    role: StaffRole.fromCode(j['role'] as String?),
    permissions: {...((j['permissions'] as List?) ?? const []).cast<String>()},
  );
}

/// Ficha de una persona del personal (directorio).
class StaffMember {
  const StaffMember({
    required this.userId,
    required this.fullName,
    required this.role,
    required this.status,
    required this.hiredOn,
    this.documentId,
    this.phone,
    this.email,
    this.terminatedOn,
    this.notes,
    this.lastSignInAt,
    this.onShiftSince,
  });

  final String userId;
  final String fullName;
  final StaffRole role;
  final StaffStatus status;
  final DateTime hiredOn;
  final String? documentId;
  final String? phone;
  final String? email;
  final DateTime? terminatedOn;
  final String? notes;
  final DateTime? lastSignInAt;

  /// Hora de entrada si ahora mismo está en turno.
  final DateTime? onShiftSince;

  bool get active => status == StaffStatus.active;
  bool get onShift => onShiftSince != null;

  StaffMember copyWith({StaffRole? role, StaffStatus? status, DateTime? onShiftSince, bool clearShift = false, StaffInput? input}) =>
      StaffMember(
        userId: userId,
        fullName: input?.fullName ?? fullName,
        role: role ?? input?.role ?? this.role,
        status: status ?? this.status,
        hiredOn: input?.hiredOn ?? hiredOn,
        documentId: input == null ? documentId : input.documentId,
        phone: input == null ? phone : input.phone,
        email: input == null ? email : input.email,
        terminatedOn: (status ?? this.status) == StaffStatus.terminated ? (terminatedOn ?? DateTime.now()) : null,
        notes: input == null ? notes : input.notes,
        lastSignInAt: lastSignInAt,
        onShiftSince: clearShift ? null : (onShiftSince ?? this.onShiftSince),
      );

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    userId: j['user_id'] as String,
    fullName: j['full_name'] as String,
    role: StaffRole.fromCode(j['role'] as String?),
    status: StaffStatus.fromCode(j['status'] as String?),
    hiredOn: DateTime.parse(j['hired_on'] as String),
    documentId: j['document_id'] as String?,
    phone: j['phone'] as String?,
    email: j['email'] as String?,
    terminatedOn: j['terminated_on'] == null ? null : DateTime.parse(j['terminated_on'] as String),
    notes: j['notes'] as String?,
    lastSignInAt: j['last_sign_in_at'] == null ? null : DateTime.parse(j['last_sign_in_at'] as String).toLocal(),
    onShiftSince: j['on_shift_since'] == null ? null : DateTime.parse(j['on_shift_since'] as String).toLocal(),
  );
}

/// Datos editables de la ficha.
class StaffInput {
  const StaffInput({required this.fullName, required this.role, this.documentId, this.phone, this.email, this.hiredOn, this.notes});

  final String fullName;
  final StaffRole role;
  final String? documentId;
  final String? phone;
  final String? email;
  final DateTime? hiredOn;
  final String? notes;
}

/// Alta: los datos de la ficha más el correo y la contraseña inicial.
class NewStaff {
  const NewStaff({required this.input, required this.email, required this.password});

  final StaffInput input;
  final String email;
  final String password;
}

/// Turno semanal. [weekday] 1 = lunes ... 7 = domingo.
class StaffShift {
  const StaffShift({required this.weekday, required this.startMinutes, required this.endMinutes});

  final int weekday;
  final int startMinutes;
  final int endMinutes;

  static const weekdayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
  String get weekdayName => weekdayNames[weekday - 1];
  int get minutes => endMinutes - startMinutes;

  static String hhmm(int minutes) => '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  String get label => '${hhmm(startMinutes)}–${hhmm(endMinutes)}';

  static int _parse(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  factory StaffShift.fromJson(Map<String, dynamic> j) =>
      StaffShift(weekday: j['weekday'] as int, startMinutes: _parse(j['starts_at'] as String), endMinutes: _parse(j['ends_at'] as String));

  Map<String, dynamic> toJson(String userId) => {
    'user_id': userId,
    'weekday': weekday,
    'starts_at': '${hhmm(startMinutes)}:00',
    'ends_at': '${hhmm(endMinutes)}:00',
  };
}

/// Una jornada (entrada y, si ya salió, salida).
class StaffTimeEntry {
  const StaffTimeEntry({required this.id, required this.userId, required this.clockIn, this.clockOut});

  final String id;
  final String userId;
  final DateTime clockIn;
  final DateTime? clockOut;

  bool get open => clockOut == null;
  Duration worked(DateTime now) => (clockOut ?? now).difference(clockIn);

  factory StaffTimeEntry.fromJson(Map<String, dynamic> j) => StaffTimeEntry(
    id: j['id'] as String,
    userId: j['user_id'] as String,
    clockIn: DateTime.parse(j['clock_in'] as String).toLocal(),
    clockOut: j['clock_out'] == null ? null : DateTime.parse(j['clock_out'] as String).toLocal(),
  );
}

/// Minutos de retraso de una entrada respecto al turno de ese día (0 si llegó
/// a tiempo o no tenía turno). Se toleran 5 minutos.
int lateMinutes(StaffTimeEntry e, List<StaffShift> shifts) {
  final shift = shifts.where((s) => s.weekday == e.clockIn.weekday).firstOrNull;
  if (shift == null) return 0;
  final arrived = e.clockIn.hour * 60 + e.clockIn.minute;
  final late = arrived - shift.startMinutes;
  return late > 5 ? late : 0;
}

/// Horas trabajadas en el mes de [month] (jornadas que empezaron ese mes).
Duration workedInMonth(List<StaffTimeEntry> entries, DateTime month, DateTime now) => entries
    .where((e) => e.clockIn.year == month.year && e.clockIn.month == month.month)
    .fold(Duration.zero, (sum, e) => sum + e.worked(now));

/// Entrada de la bitácora.
class AuditEntry {
  const AuditEntry({required this.at, required this.action, required this.entity, this.userName, this.entityId, this.detail = const {}});

  final DateTime at;
  final String? userName;
  final String action;
  final String entity;
  final String? entityId;
  final Map<String, dynamic> detail;

  /// Frase legible de la acción.
  String get description {
    String d(String k) => '${detail[k] ?? ''}';
    String role(String k) => StaffRole.values.where((r) => r.code == detail[k]).firstOrNull?.label ?? d(k);
    String status(String k) => StaffStatus.values.where((s) => s.code == detail[k]).firstOrNull?.label ?? d(k);
    String perm(String k) => permissionCatalog.where((p) => p.code == detail[k]).firstOrNull?.label ?? d(k);
    return switch (action) {
      'payment.void' => 'Anuló un pago · ${d('reason')}',
      'sale.void' => 'Anuló una venta · ${d('reason')}',
      'purchase.void' => 'Anuló una compra · ${d('reason')}',
      'stock.adjust' => 'Ajustó stock (${d('quantity')}) · ${d('note')}',
      'product.price' => 'Cambió el precio de ${d('name')}',
      'plan.create' => 'Creó el plan ${d('name')}',
      'plan.update' => 'Editó el plan ${d('name')}',
      'settings.update' => entity == 'payment_methods' ? 'Cambió un método de pago' : 'Cambió la tasa de cambio',
      'member.delete' => 'Eliminó al cliente ${d('name')}',
      'member.deactivate' => 'Desactivó al cliente ${d('name')}',
      'staff.create' => 'Dio de alta a ${d('name')} como ${role('role')}',
      'staff.role' => 'Cambió el rol de ${d('name')}: ${role('from')} → ${role('to')}',
      'staff.status' => '${d('name')}: ${status('from')} → ${status('to')}',
      'staff.password' => 'Cambió la contraseña de una cuenta',
      'role.grant' => '${role('_role')}: permitió «${perm('permission')}»',
      'role.revoke' => '${role('_role')}: quitó «${perm('permission')}»',
      _ => action,
    };
  }

  factory AuditEntry.fromJson(Map<String, dynamic> j, Map<String, String> names) {
    final detail = Map<String, dynamic>.from((j['detail'] as Map?) ?? const {});
    if (j['entity'] == 'role_permissions') detail['_role'] = j['entity_id'];
    return AuditEntry(
      at: DateTime.parse(j['at'] as String).toLocal(),
      userName: names[j['user_id']],
      action: j['action'] as String,
      entity: j['entity'] as String,
      entityId: j['entity_id'] as String?,
      detail: detail,
    );
  }
}
