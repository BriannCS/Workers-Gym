# Control de personal y roles · Estructura

Hecho por Briann$ - Workers Corp. · v1 implementada · 16/10/2026

## 1. Situación actual

- `public.staff` solo tiene `user_id`, `full_name` y `created_at`.
- La seguridad es de todo o nada: `private.is_staff()` deja leer y escribir **todo** a cualquier cuenta del personal.
- Las cuentas se crean a mano en el panel de Supabase.
- No hay forma de saber qué empleado hizo cada cobro o venta, salvo en las anulaciones (`voided_by`).

## 2. Objetivo

1. Cada persona entra con su cuenta y **solo ve y hace lo que su rol permite**.
2. Los permisos se aplican **en la base de datos (RLS)**, no solo ocultando botones. Aunque alguien manipule la app, Supabase rechaza la acción.
3. El dueño gestiona al personal desde la app: altas, rol, suspensión y bajas, sin entrar a Supabase.
4. Queda registro de quién hizo qué, y de las entradas y salidas del personal.

## 3. Roles

| Rol | Para quién | Resumen |
| --- | --- | --- |
| **Dueño** | Brian / propietario | Todo. Único que gestiona personal, roles y ajustes críticos. Nunca puede quedar el gimnasio sin al menos un dueño activo. |
| **Administrador** | Gerente | Todo lo operativo y los reportes. Gestiona personal, pero no puede crear ni modificar dueños. |
| **Recepción** | Recepcionista / cajero | Día a día: asistencia, clientes, cobros, tienda y su propia caja. No anula, no ve reportes globales ni ajustes. |
| **Entrenador** | Coach | Asistencia y consulta de clientes (sin datos de pago). Marca su entrada y salida. |

## 4. Permisos por módulo

✔ = sí · 👁 = solo ver · — = no

| Permiso | Dueño | Admin | Recepción | Entrenador |
| --- | --- | --- | --- | --- |
| Inicio (resumen del día) | ✔ | ✔ | ✔ | 👁 sin montos |
| Asistencia: registrar entrada | ✔ | ✔ | ✔ | ✔ |
| Asistencia: borrar registro | ✔ | ✔ | — | — |
| Clientes: ver | ✔ | ✔ | ✔ | 👁 sin pagos |
| Clientes: crear / editar | ✔ | ✔ | ✔ | — |
| Clientes: desactivar / eliminar | ✔ | ✔ | — | — |
| Pagos: cobrar | ✔ | ✔ | ✔ | — |
| Pagos: anular | ✔ | ✔ | — | — |
| Tienda: vender | ✔ | ✔ | ✔ | — |
| Inventario y compras | ✔ | ✔ | 👁 | — |
| Caja: ver la propia | ✔ | ✔ | ✔ | — |
| Caja: ver la de todos / cierre Z | ✔ | ✔ | — | — |
| Planes y precios | ✔ | ✔ | 👁 | — |
| Ajustes: tasa y métodos de pago | ✔ | ✔ | — | — |
| **Personal: ver** | ✔ | ✔ | — | — |
| **Personal: crear / editar / suspender** | ✔ | ✔ (no dueños) | — | — |
| **Roles: cambiar permisos** | ✔ | — | — | — |
| Bitácora de actividad | ✔ | ✔ | — | — |

Los permisos viven en una tabla, así que el dueño podrá ajustarlos sin tocar código.

## 5. Módulo "Personal" (nueva sección en el menú)

### 5.1 Lista del personal
- Foto, nombre, rol (etiqueta de color), estado (activo / suspendido) y estado de hoy (en turno / fuera).
- Filtros por rol y estado, y búsqueda por nombre o cédula.

### 5.2 Ficha del empleado
- **Datos:** nombre, cédula, teléfono, correo, foto, fecha de ingreso, notas.
- **Acceso:** rol, cuenta activa o suspendida, último ingreso a la app.
- **Turnos:** horario semanal (por ejemplo, lunes a viernes de 6:00 a 14:00).
- **Asistencia del personal:** historial de entradas y salidas, horas trabajadas en el mes y retrasos.
- **Actividad:** cobros, ventas y anulaciones que hizo.

### 5.3 Alta de personal
1. El dueño o admin llena nombre, correo, cédula, rol y una **contraseña inicial**.
2. La app llama a la **Edge Function `staff-admin`**, que comprueba con el token de quien llama que tenga `staff.manage` y crea la cuenta con la clave de servicio. La clave nunca está en la app.
3. Se le entrega la contraseña en persona; la persona puede cambiarla en Ajustes › Mi cuenta. El dueño o admin también puede reponerla desde la ficha.

Se eligió contraseña inicial en vez de invitación por correo porque el enlace del correo no abre la APK de Android.

### 5.4 Suspender y dar de baja
- **Suspender:** bloquea el acceso de inmediato y conserva el historial.
- **Baja:** marca la fecha de salida. Nunca se borran los registros de cobros o ventas que hizo.

### 5.5 Entrada y salida del personal
- Botón "Marcar entrada / salida" visible para cada empleado al iniciar sesión.
- Calcula horas trabajadas y retrasos contra su turno.

### 5.6 Bitácora
- Registro automático (por trigger) de las acciones sensibles: anulaciones, eliminaciones, cambios de precio, cambios de rol, suspensiones y cierres de caja.

## 6. Base de datos (Supabase)

```text
staff (ampliada)
  user_id PK → auth.users
  full_name, id_number (cédula), phone, email, photo_path
  role            → 'owner' | 'admin' | 'reception' | 'trainer'
  status          → 'active' | 'suspended' | 'terminated'
  hired_on, terminated_on, notes, created_at

role_permissions
  role, permission (p. ej. 'payments.void', 'staff.manage')   PK (role, permission)

staff_shifts            turno semanal
  id, user_id, weekday (1-7), starts_at, ends_at

staff_attendance        entradas y salidas del personal
  id, user_id, clock_in, clock_out, note

audit_log               bitácora
  id, at, user_id, action, entity, entity_id, detail jsonb
```

**Columnas nuevas en tablas existentes:** `created_by` en `payments`, `sales`, `attendance` y `purchases`, con valor por defecto `auth.uid()`. Así sabemos quién hizo cada movimiento sin cambiar la app.

**Funciones de seguridad (en el esquema `private`):**
- `private.current_role()` devuelve el rol del usuario, o nulo si no está activo.
- `private.can(permission text)` dice si el rol actual tiene ese permiso.
- `private.is_staff()` pasa a exigir además `status = 'active'`. Así, suspender a alguien lo bloquea al instante en todas las tablas.

**Políticas RLS:** las actuales `staff_only` se reemplazan por políticas por acción. Por ejemplo, en `payments` el `insert` exige `can('payments.create')` y el `update` exige `can('payments.void')`.

**Regla de protección:** un trigger impide desactivar o degradar al último dueño activo.

## 7. App (Flutter)

- `domain/models.dart`: `StaffRole`, `StaffMember`, `Permission` y `StaffShift`.
- `currentStaffProvider` devuelve el `StaffMember` completo (rol y permisos), no solo el nombre.
- Router: cada `AppSection` declara el permiso que necesita. El menú oculta lo que no corresponde, y la ruta redirige si alguien entra por URL.
- Widget `Can(permission, child)` para ocultar botones como "Anular" o "Eliminar".
- Nueva sección `features/staff/` con lista, ficha, alta y la pantalla de entrada/salida.
- El repositorio demo tendrá personal de ejemplo con los 4 roles, y en modo demo se podrá cambiar de rol para probar.

## 8. Orden de implementación

1. **Migración**: ampliar `staff`, crear `role_permissions` y las funciones `private.current_role()` y `private.can()`. Asignar rol `owner` a las cuentas que ya existen, para que nadie pierda acceso.
2. **RLS por permiso** en todas las tablas, más `created_by` en los movimientos.
3. **App: roles y permisos.** Modelo, provider, menú, rutas y botones filtrados.
4. **Sección Personal**: lista, ficha, edición, suspensión.
5. **Edge Function `staff-invite`** y pantalla de alta.
6. **Turnos y entrada/salida** del personal.
7. **Bitácora** con triggers y su pantalla.
8. **Pruebas**: tests de la app por rol, y pruebas SQL que confirmen que Recepción no puede anular pagos ni ver al personal.

## 9. Fuera de esta fase

- Nómina y pagos al personal.
- Comisiones de entrenadores o ventas.
- Cuentas para clientes (app del socio).

## 10. Estado de la implementación (16/10/2026)

| Parte | Dónde | Estado |
| --- | --- | --- |
| Migración de roles, permisos, triggers, turnos, marcaje y bitácora | `supabase/migrations/20261016214726_staff_roles.sql` | Aplicada en producción. Probada por rol en transacción revertida. |
| Edge Function de alta y contraseñas | `supabase/functions/staff-admin/index.ts` | Desplegada (v1, `verify_jwt` activo). |
| Modelo y repositorio | `lib/domain/staff.dart`, `lib/data/gym_repository.dart`, `lib/data/demo_gym_repository.dart` | Hecho. El demo aplica las mismas reglas que el servidor. |
| Menú, botones y caja por rol | `lib/core/router/app_router.dart`, pantallas en `lib/features/` | Hecho. |
| Sección Personal (equipo, ficha, turnos, jornadas, roles, bitácora) | `lib/features/staff/staff_screen.dart` | Hecho. |
| Marcar entrada / salida | `lib/core/widgets/staff_controls.dart` | En el menú lateral y en "Más" del teléfono. |
| Pruebas | `test/staff_roles_test.dart` | 13 pruebas nuevas; 80 en total pasan. |

**Pendiente / ideas siguientes:** foto del empleado, corrección manual de jornadas olvidadas por un admin, exportar horas del mes, y probar en un dispositivo real que, al suspender a alguien, su app cambie sola a "Tu cuenta no tiene acceso" (debería ocurrir por tiempo real sobre la tabla `staff`; los datos ya se le niegan al instante en el servidor).
