# Pendientes de Workers Gym

Hecho por Briann$ - Workers Corp.

Ideas y tareas acordadas. Las hechas quedan abajo con su estado para saber cómo funcionan.

## Pagos

### Pago móvil con comprobante (pedido por Brian, 16/10/2026)
- Registrar pagos hechos por **pago móvil**: banco de origen, teléfono o cédula del pagador, número de referencia y monto en bolívares, con la tasa del día.
- **Foto del comprobante**: tomarla con la cámara o elegirla de la galería al registrar el pago, y verla luego en el detalle del pago y en el historial del cliente.
- Ideas a revisar al diseñarlo:
  - Guardar la foto en Supabase Storage, en un bucket privado como `payment-receipts` (igual que las fotos de clientes), visible solo con `payments.view`.
  - Que no se repita la misma referencia del mismo banco, para evitar cobrar dos veces el mismo pago.
  - Estado "por verificar" / "verificado" para que el dueño o el administrador confirme contra el banco.
  - Al anular el pago, conservar el comprobante.

## Compras

### Método de pago y moneda en cada compra (pedido por Brian, 16/10/2026)
- Indicar con qué se pagó la compra al proveedor (efectivo $, efectivo Bs., transferencia, pago móvil, etc.), usando los mismos métodos de pago de Ajustes.
- Si fue en **bolívares**: guardar el monto en Bs. y la tasa del día, igual que en los cobros, para saber el equivalente exacto en dólares.
- Si fue en **dólares**: el monto en $.
- Objetivo: llevar el control exacto de cuánto salió en cada moneda (resumen del mes de compras en $ y en Bs.).

### Crear un producto nuevo desde la compra (pedido por Brian, 16/10/2026)
- Al cargar una factura, si el producto aún no existe, poder crearlo ahí mismo (nombre, código, precio de venta y stock mínimo) sin salir de la compra.
- El costo y el proveedor se toman de la misma compra; el stock nace con la cantidad comprada.
- Solo para quien tenga permiso de gestionar inventario.

## Inventario

### Escanear el código (SKU) con la cámara (pedido por Brian, 16/10/2026)
- En el campo "Código (SKU)" del producto, un botón de cámara que lea el código de barras o QR del empaque y lo rellene solo.
- Útil también en Compras (buscar el producto al escanearlo) y en Tienda (agregarlo al carrito escaneando).
- Si el código escaneado ya existe, abrir ese producto en vez de crear uno repetido.
- Revisar en Android, iPhone y la web (en la web pide permiso de cámara).

## Estado (17/10/2026): los cuatro implementados

| Pendiente | Cómo quedó |
| --- | --- |
| Pago móvil con comprobante | Al cobrar (membresía o tienda) con un método que **pide referencia** aparecen: referencia *, banco (lista de bancos venezolanos), cédula/teléfono de quien pagó y la foto (cámara o galería). Sin referencia no se puede cobrar. La misma referencia del mismo banco no se acepta dos veces (ni entre cobros y ventas), salvo que el primero esté anulado. |
| Verificación | Cada pago con referencia queda **POR VERIFICAR**. Dueño y administrador (permiso nuevo `payments.verify`) lo marcan **VERIFICADO** desde el comprobante. En Pagos hay un filtro "Por verificar". |
| Foto del comprobante | Bucket privado `payment-receipts` (5 MB, jpg/png/webp). Recepción sube la foto al cobrar o después desde el detalle; solo quien cobró o un verificador puede cambiarla. Si la subida falla, el cobro queda y se avisa. |
| Qué métodos piden referencia | Ajustes › Métodos de pago › ficha **Ref.** en cada método. Vienen marcados: pago móvil, transferencia, Zelle y Binance. |
| Compras con método y moneda | Cada compra exige "¿con qué se le pagó al proveedor?". Si es en Bs. guarda la tasa del día y el total en Bs.; referencia opcional. Compras muestra lo pagado en $ y en Bs. del mes. Las compras viejas quedan "Sin indicar". |
| Producto nuevo desde la compra | Botón ➕ en cada línea: nombre, código, precio y mínimo; el costo y el proveedor salen de la compra y el stock entra con la compra. |
| Escanear el código | Botón de cámara en el código del producto, en cada línea de compra y en la búsqueda de la Tienda (escanea y agrega al carrito). Un código repetido avisa y ofrece abrir el producto existente. En la PC con Windows (app de escritorio) no hay botón: el lector USB escribe el código y Enter. En la web usa el lector del navegador o ZXing servido desde la app (`web/zxing/`, licencia Apache 2.0). |

Base de datos: migración `supabase/migrations/20261017050132_payment_proofs_purchase_methods.sql`, probada por rol en una transacción revertida y **aplicada en producción** el 17/10/2026.
Pruebas: `test/payments_proof_test.dart` (14) + ajustes en las existentes; 100 en total.

**Falta probar en equipos reales:** cámara del escáner en Android/iPhone y en el navegador de la PC, y la subida de la foto a Supabase con una cuenta real.
