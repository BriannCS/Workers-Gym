// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/core/theme/app_theme.dart';
import 'package:gimnasio_app/features/auth/login_screen.dart';
import 'package:gimnasio_app/core/widgets/brand_mark.dart';
import 'package:gimnasio_app/core/widgets/ui.dart';
import 'package:gimnasio_app/data/demo_gym_repository.dart';
import 'package:gimnasio_app/domain/models.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  setUpAll(initTestLocale);

  testWidgets('todas las secciones cargan sin errores', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    expect(find.text('HOY'), findsOneWidget);
    expect(find.textContaining('LLAMAR PARA RENOVAR'), findsOneWidget);

    for (final (section, marker) in [
      ('Asistencia', 'QUIÉN LLEGA'),
      ('Clientes', 'María Fernanda Rojas'),
      ('Pagos', 'ASIENTOS'),
      ('Tienda', 'VENTA EN CURSO'),
      ('Inventario', 'VALOR DEL INVENTARIO'),
      ('Compras', 'FACTURAS'),
      ('Caja', 'POR MÉTODO'),
      ('Planes', 'TRIMESTRAL'),
      ('Ajustes', 'MÉTODOS DE PAGO · 6'),
    ]) {
      await goTo(tester, section);
      expect(find.text(marker), findsWidgets, reason: section);
    }
  });

  // Cada sección en teléfono y tableta: cualquier desborde de layout es una
  // excepción en el test.
  for (final (name, size) in [('teléfono', phoneSize), ('tableta', tabletSize)]) {
    testWidgets('en $name todas las secciones caben y se navegan', (tester) async {
      useDesktopWindow(tester, size: size);
      await tester.pumpWidget(buildTestApp());
      await tester.pumpAndSettle();
      expect(find.text('HOY'), findsOneWidget);

      for (final section in ['Asistencia', 'Clientes', 'Pagos', 'Tienda', 'Inventario', 'Compras', 'Caja', 'Planes', 'Personal', 'Entrenos', 'Ajustes', 'Inicio']) {
        await goTo(tester, section);
        expect(tester.takeException(), isNull, reason: '$section en $name');
      }
    });
  }

  testWidgets('en teléfono el carrito se cobra desde la hoja inferior', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Tienda');

    await tester.tap(find.text('Agua mineral 600 ml'));
    await tester.pumpAndSettle();
    expect(find.text('1 ARTÍCULO'), findsOneWidget);

    await tester.tap(find.text('1 ARTÍCULO'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, r'Cobrar $1,00'));
    await tester.pumpAndSettle();

    expect((await repo.sales()).first.description, 'Agua mineral 600 ml');
    expect(find.text('1 ARTÍCULO'), findsNothing);
  });

  testWidgets('en teléfono los formularios ocupan la pantalla completa', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');
    await tester.tap(find.widgetWithText(FilledButton, 'Nuevo cliente'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(FormDialog)).width, phoneSize.width);
  });

  testWidgets('en teléfono, mantener presionado un cliente permite desactivarlo y eliminarlo', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');

    final luis = find.text('Luis Alberto Méndez');
    await tester.ensureVisible(luis);
    await tester.pumpAndSettle();
    await tester.longPress(luis);
    await tester.pumpAndSettle();
    expect(find.text('Editar datos'), findsOneWidget);
    expect(find.text('Eliminar cliente'), findsOneWidget);

    await tester.tap(find.text('Marcar como inactivo'));
    await tester.pumpAndSettle();
    expect((await repo.members()).firstWhere((m) => m.fullName.startsWith('Luis')).active, isFalse);

    await tester.ensureVisible(luis);
    await tester.pumpAndSettle();
    await tester.longPress(luis);
    await tester.pumpAndSettle();
    expect(find.text('Marcar como activo'), findsOneWidget);
    await tester.tap(find.text('Eliminar cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
    await tester.pumpAndSettle();

    expect((await repo.members()).any((m) => m.fullName.startsWith('Luis')), isFalse);
    expect(find.text('Luis Alberto Méndez'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // El ancho real de los botones en 360 px se revisa con fuentes reales en
  // screenshots_test.dart ("capturas teléfono angosto"): la fuente de prueba
  // de Flutter es más ancha y daría desbordes falsos.
  testWidgets('la ficha del cliente en teléfono usa botones cortos y opciones arriba', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');
    await tester.ensureVisible(find.text('Luis Alberto Méndez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luis Alberto Méndez'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Entrada'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Cobrar'), findsOneWidget);
    expect(find.byTooltip('Más opciones'), findsWidgets);
  });

  testWidgets('el inicio de sesión lleva la firma', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    await tester.pumpWidget(const ProviderScope(child: MaterialApp(home: LoginScreen())));
    await tester.pumpAndSettle();
    expect(find.text(brandSignature), findsOneWidget);
  });

  testWidgets('check-in con Enter registra al primer resultado', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    final before = (await repo.attendanceSince(DateTime(2026, 9, 28))).length;
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Asistencia');

    await tester.enterText(find.byType(TextField), 'Andrea');
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect((await repo.attendanceSince(DateTime(2026, 9, 28))).length, before + 1);
    expect(find.text('BIENVENIDO'), findsOneWidget);
    expect(find.text('ANDREA VALENTINA GÓMEZ'), findsOneWidget);
  });

  testWidgets('cobrar a un cliente vencido lo deja solvente', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');

    final luis = (await repo.members()).firstWhere((m) => m.fullName.startsWith('Luis'));
    expect(luis.status(testNow), MembershipStatus.expired);

    final row = find.ancestor(of: find.text('Luis Alberto Méndez'), matching: find.byType(InkWell)).first;
    final payButton = find.descendant(of: row, matching: find.byTooltip('Registrar pago'));
    await tester.ensureVisible(payButton);
    await tester.pumpAndSettle();
    await tester.tap(payButton);
    await tester.pumpAndSettle();
    expect(find.text('NUEVO PERIODO'), findsOneWidget);

    await tester.tap(find.textContaining('Cobrar \$'));
    await tester.pumpAndSettle();

    final members = await repo.members();
    final updated = members.firstWhere((m) => m.fullName.startsWith('Luis'));
    expect(updated.status(testNow), MembershipStatus.active);
    expect(updated.expiresOn, DateTime.utc(2026, 10, 27)); // vencido: 30 días desde hoy
  });

  testWidgets('registrar cliente nuevo valida y guarda', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');

    await tester.tap(find.widgetWithText(FilledButton, 'Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Ingresa el nombre y apellido'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nombre completo *'), 'Pedro Pablo León');
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar cliente'));
    await tester.pumpAndSettle();

    expect((await repo.members()).any((m) => m.fullName == 'Pedro Pablo León'), isTrue);
    expect(find.byType(FormDialog), findsNothing);
    expect(find.text('Pedro Pablo León'), findsOneWidget);
  });

  testWidgets('vender desde la tienda descuenta stock y aparece en caja', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Tienda');

    final before = (await repo.products()).firstWhere((p) => p.name == 'Bebida isotónica').stock;
    await tester.tap(find.text('Bebida isotónica'));
    await tester.tap(find.text('Bebida isotónica'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, r'Cobrar $5,00'));
    await tester.pumpAndSettle();

    expect((await repo.products()).firstWhere((p) => p.name == 'Bebida isotónica').stock, before - 2);
    expect(find.text('Toca una etiqueta para agregarla.'), findsOneWidget);

    await goTo(tester, 'Caja');
    expect(find.text('2× Bebida isotónica'), findsOneWidget);
  });

  testWidgets('anular un pago desde el historial pide motivo', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Pagos');

    await tester.tap(find.byTooltip('Anular pago').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();
    expect(find.text('El motivo es obligatorio'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Cobrado dos veces');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular'));
    await tester.pumpAndSettle();

    expect((await repo.payments()).where((p) => p.voided).length, 1);
    expect(find.text('ANULADO'), findsOneWidget);
  });

  testWidgets('modo oscuro con un clic, sin perder la pantalla', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');
    expect(AppColors.isDark, isFalse);

    await tester.tap(find.byTooltip('Modo oscuro'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.text('CLIENTES'), findsWidgets); // sigue en la misma sección
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Modo claro'));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isFalse);
  });

  testWidgets('cobrar en bolívares usa la tasa vigente', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');

    final row = find.ancestor(of: find.text('Luis Alberto Méndez'), matching: find.byType(InkWell)).first;
    final payButton = find.descendant(of: row, matching: find.byTooltip('Registrar pago'));
    await tester.ensureVisible(payButton);
    await tester.pumpAndSettle();
    await tester.tap(payButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pago móvil'));
    await tester.pumpAndSettle();
    // Mensual $30 × 800 (BCV dólar de prueba) = Bs. 24.000,00
    expect(find.text('Bs. 24.000,00'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cobrar Bs. 24.000,00'));
    await tester.pumpAndSettle();

    final paid = (await repo.payments()).first;
    expect(paid.methodCode, 'pago_movil');
    expect(paid.amountVesCents, 2400000);
    expect(paid.rateSource, RateSource.bcvUsd);
  });

  testWidgets('registrar una compra suma al stock', (tester) async {
    useDesktopWindow(tester);
    final repo = DemoGymRepository.seeded(clock: () => testNow);
    final before = (await repo.products()).firstWhere((p) => p.name == 'Shaker 700 ml').stock;
    await tester.pumpWidget(buildTestApp(repo: repo));
    await tester.pumpAndSettle();
    await goTo(tester, 'Compras');

    await tester.tap(find.widgetWithText(FilledButton, 'Nueva compra'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(DropdownMenu<Product>), matching: find.byType(TextField)), 'Shaker');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(MenuItemButton, 'Shaker 700 ml').last); // la primera es la copia de medición
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cant.'), '12');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, r'Registrar $42,00')); // 12 × $3,50
    await tester.pumpAndSettle();

    expect((await repo.products()).firstWhere((p) => p.name == 'Shaker 700 ml').stock, before + 12);
    expect((await repo.purchases()).first.totalCents, 4200);
  });

  testWidgets('un método agregado en Ajustes aparece al cobrar', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Ajustes');

    await tester.enterText(find.widgetWithText(TextField, 'Ej. Pago móvil BDV, PayPal'), 'PayPal');
    await tester.tap(find.text('En dólares'));
    await tester.tap(find.widgetWithText(FilledButton, 'Agregar'));
    await tester.pumpAndSettle();
    expect(find.text('PayPal'), findsOneWidget);

    await goTo(tester, 'Tienda');
    expect(find.text('PayPal'), findsOneWidget);
  });

  testWidgets('tocar un movimiento de caja muestra su detalle', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Caja');

    await tester.tap(find.text('Bebida isotónica, Barra de proteína'));
    await tester.pumpAndSettle();
    expect(find.text('VENTA DE TIENDA'), findsOneWidget);
    expect(find.text('1 × Barra de proteína'), findsOneWidget);
    expect(find.text('Tasa BCV dólar'), findsOneWidget); // fue en pago móvil
  });

  testWidgets('la cédula no acepta letras', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await tester.pumpAndSettle();
    await goTo(tester, 'Clientes');
    await tester.tap(find.widgetWithText(FilledButton, 'Nuevo cliente'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Cédula'), 'abc12345678x');
    await tester.enterText(find.widgetWithText(TextFormField, 'Teléfono'), '0426abc9998877');
    await tester.pump();
    expect(find.text('12.345.678'), findsOneWidget);
    expect(find.text('0426-999-8877'), findsOneWidget);
  });
}
