# Workers Gym — Workers Recepción

App de recepción de gimnasio (Flutter: PWA, escritorio y teléfono) para clientes, membresías, pagos en dólares o bolívares, asistencia, tienda, compras, inventario y cierre de caja. Backend en **Supabase** (Postgres + Auth + Realtime + Storage).

## Ejecutar

Sin credenciales la app arranca en **modo demo** con datos de prueba en memoria:

```sh
flutter run -d chrome          # o -d windows / -d web-server --web-port=8080
```

Con Supabase:

1. Aplica las migraciones de [supabase/migrations/](supabase/migrations/) en orden (MCP `apply_migration`, *SQL Editor* o `supabase db push`).
2. En *Authentication → Users*, crea la cuenta de cada empleado y regístrala como personal:
   ```sql
   insert into public.staff (user_id, full_name)
   select id, 'Nombre Apellido' from auth.users where email = 'recepcion@tu-gimnasio.com';
   ```
   Estar autenticado **no** da acceso: solo las cuentas en `public.staff` ven datos (RLS). Aun así, desactiva el registro público en *Authentication → Sign In / Providers → Allow new users to sign up*.
3. `env.json` (ignorado por git) lleva la URL, la *publishable key* y `GYM_NAME`; ver `env.example.json`.
4. `flutter run -d windows --dart-define-from-file=env.json`

El MCP de Supabase está configurado en `.mcp.json` (proyecto `oppbuyitotxnmftbvzyw`); la primera vez hay que autenticarlo con `/mcp`.

## GitHub: PWA y APK automáticos

[.github/workflows/publicar.yml](.github/workflows/publicar.yml) corre en cada `push` a `main`:

1. `flutter analyze` + `flutter test`.
2. Compila la PWA y la publica en **GitHub Pages** (`https://<usuario>.github.io/<repositorio>/`), con la política de seguridad (CSP) dentro de `index.html`.
3. Compila el **APK de Android** firmado → pestaña *Actions* → la ejecución → *Artifacts* → `workers-gym-apk`. Con una etiqueta (`git tag v1.0.0 && git push --tags`) además crea una *Release* con el APK adjunto.

Configuración única del repositorio:

- *Settings → Pages → Source*: **GitHub Actions**.
- *Settings → Secrets and variables → Actions*: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`. La llave de firma vive **fuera del repositorio**; si se pierde, los teléfonos no podrán actualizar la app (habría que reinstalarla).
- En Supabase, *Authentication → URL Configuration*: agrega la URL de GitHub Pages.

En el iPhone se usa la PWA: abrir la URL en Safari → *Compartir* → *Agregar a pantalla de inicio*. Una app iOS nativa requiere Mac/Xcode y una cuenta de Apple Developer.

### Requisitos para Windows

- Visual Studio 2022 con la carga de trabajo **"Desarrollo para el escritorio con C++"**.
- **Modo de desarrollador** activado en Windows (`start ms-settings:developers`); lo exigen los plugins.

## Dinero, tasa y métodos de pago

- Los precios están en **dólares** (centavos, `int`). Si se cobra con un método en bolívares, el monto en Bs. es `precio × tasa`, y **la tasa usada queda guardada en el pago o la venta** (`rate`, `rate_source`, `amount_ves_cents`). El servidor recalcula el monto en Bs.
- **Tasa** (en *Ajustes*, compartida entre dispositivos): BCV dólar, BCV euro, paralelo o manual. Las tres primeras se consultan en vivo a `ve.dolarapi.com` (misma fuente y regla del Apps Script "Visor de Cambios": promedio → venta → compra), con caché de 15 min. La API tiene CORS abierto, así que la PWA la consulta directo. Sin conexión: tasa manual.
- **Métodos de pago** (en *Ajustes*): Efectivo ($), Efectivo (Bs.), Transferencia, Pago móvil, Binance, Zelle, más los que se agreguen. "Quitar" los desactiva (no se borran, para no romper el historial) y se pueden restaurar.
- **Cierre de caja**: totales por método en su moneda (Bs. con su equivalente en $), detalle de cada movimiento, exportar **PDF** (ticket de 80 mm), **imprimir** y compartir por **WhatsApp**.

## Inventario y compras

`stock actual = stock inicial ± ajustes + compras − ventas` (sin contar anuladas).

- **Compras** (proveedor, factura, fecha, productos con cantidad y costo) suman al stock y actualizan el costo del producto. Anular una compra retira esas unidades; si ya se vendieron, no se puede.
- **Ajustes de inventario** (merma, conteo) restan o suman con motivo obligatorio.
- `products.stock` se mantiene en la misma transacción que cada compra/venta/ajuste; la vista SQL `product_stock_audit` recalcula el stock desde los registros para auditarlo.

## Clientes

- Foto de perfil desde la **cámara** (en el teléfono abre la cámara directamente) o la galería; se reduce a 600 px y se guarda en un bucket privado de Supabase Storage (solo personal).
- **Cédula**: nacionalidad V/E + solo números ("V-24.518.330"). **Teléfono**: solo números ("0414-555-0192"). Los campos no aceptan letras ni símbolos; tampoco los de precios, costos y cantidades.

## PWA y sincronización

La web (PWA) y la app del teléfono son **el mismo código**; se mantienen sincronizadas a través de Supabase:

- **Tiempo real:** [lib/data/sync.dart](lib/data/sync.dart) abre un canal de Supabase Realtime (Postgres Changes) y recarga solo lo que cambió cuando otro dispositivo escribe. Al reconectar o volver de segundo plano recarga todo. Indicador *En vivo / Conectando / Sin conexión* en el menú.
- **Sin conexión:** Flutter 3.47 ya no genera un service worker útil, así que [web/sw.js](web/sw.js) da el modo offline (red primero, caché de respaldo, nunca guarda datos de Supabase). Cobros y ventas requieren conexión a propósito.
- **Publicar:**
  ```sh
  flutter build web --wasm --no-web-resources-cdn --dart-define-from-file=env.json
  ```
  Sube `build/web` a un hosting estático con **HTTPS** (Cloudflare Pages, Netlify, Vercel, Firebase Hosting). En el teléfono: abrir la URL → *Agregar a pantalla de inicio*.
  `--no-web-resources-cdn` empaqueta CanvasKit en la app (sin código de gstatic.com); [web/_headers](web/_headers) aplica la política de seguridad (CSP, anti-iframe, HSTS) en Netlify/Cloudflare Pages. En otro hosting, copia esos encabezados a su configuración.

## Seguridad

- Solo el **personal** (`public.staff`) ve o toca datos; estar registrado no basta. El registro público está desactivado.
- El dinero y el stock **solo** cambian por funciones del servidor que validan quién llama, la fecha, la tasa (±50 % de la usada en los últimos 7 días) y el motivo de cada anulación. Las tablas no aceptan escritura directa de pagos, ventas, compras, stock ni anulaciones ([migración de endurecimiento](supabase/migrations/20261014000000_security_hardening.sql)).
- Cédula, teléfono, correo y largos de texto se validan también en la base de datos.
- Iconos (mismo dibujo del disco que usa la app): `flutter test test/generate_icons_test.dart --run-skipped`.

## Diseño

La recepción como el cuaderno de entrenamiento de un gimnasio: papel y tinta de día, **pizarra y tiza de noche** (modo claro/oscuro con un clic, por dispositivo), líneas de cuaderno, sellos de goma para el estado de membresía y los colores de los discos olímpicos (azul 20 kg, rojo 25, amarillo 15, verde 10) como única paleta. Tipografías empaquetadas: Big Shoulders, Archivo, IBM Plex Mono. Tokens en [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart) (`ModeColor`: cada token tiene valor claro y oscuro), componentes en [lib/core/widgets/ui.dart](lib/core/widgets/ui.dart).

Composición adaptable: lomo con pestañas numeradas en escritorio (≥ 1100 px), lomo compacto en tableta, barra inferior + "Más" en teléfono (< 640 px); tablas que pasan a fichas y formularios a pantalla completa en pantallas angostas.

## Estructura

```
lib/
  domain/models.dart             Entidades y reglas de negocio puras
  data/gym_repository.dart       Interfaz del repositorio, implementación Supabase y providers (Riverpod)
  data/demo_gym_repository.dart  Implementación en memoria (modo demo y tests), mismas reglas que el SQL
  data/rates.dart                Tasas BCV/euro/paralelo (ve.dolarapi.com)
  data/sync.dart                 Sincronización en tiempo real
  core/                          Tema y modo oscuro, router, formatos, filtros de escritura, componentes UI
  features/                      Una carpeta por sección
supabase/migrations/             Esquema SQL
```

Secciones: Inicio, Asistencia, Clientes, Pagos, Tienda, Inventario, Compras, Caja, Planes y Ajustes.

## Tests

```sh
flutter test
# Capturas (claro, oscuro, escritorio y teléfono) en test/screenshots/ (requiere FLUTTER_ROOT):
flutter test test/screenshots_test.dart --run-skipped --update-goldens
```
