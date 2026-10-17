// Hecho por Briann$ - Workers Corp.
// Pago móvil con comprobante, compras con método de pago, productos creados
// desde la compra y escaneo de códigos. Las reglas del demo son las mismas
// que aplican las funciones de Supabase.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/core/widgets/ui.dart';
import 'package:gimnasio_app/data/demo_gym_repository.dart';
import 'package:gimnasio_app/domain/models.dart';
import 'package:gimnasio_app/domain/staff.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

void main() {
  setUpAll(initTestLocale);

  const rate = ExchangeRate(RateSource.bcvUsd, 800);
  late DemoGymRepository repo;
  late PaymentMethod pagoMovil, efectivoUsd;
  late Member luis;
  late Plan monthly;

  setUp(() async {
    repo = DemoGymRepository.seeded(clock: () => testNow);
    final methods = await repo.paymentMethods();
    pagoMovil = methods.firstWhere((m) => m.code == 'pago_movil');
    efectivoUsd = methods.firstWhere((m) => m.code == 'efectivo_usd');
    luis = (await repo.members()).firstWhere((m) => m.fullName.startsWith('Luis'));
    monthly = (await repo.plans()).firstWhere((p) => p.name == 'Mensual');
  });

  NewPayment pay(PaymentMethod m, {ProofInput proof = const ProofInput()}) =>
      NewPayment.renewal(member: luis, plan: monthly, method: m, today: testNow, rate: m.inBolivares ? rate : null, proof: proof);

  group('pago móvil con comprobante', () {
    test('pide la referencia y la guarda sin espacios', () async {
      expect(pay(pagoMovil).ready, isFalse);
      await expectLater(repo.addPayment(pay(pagoMovil)), throwsA(isA<GymException>()));

      final paid = await repo.addPayment(
        pay(
          pagoMovil,
          proof: const ProofInput(reference: ' 0102 9988 ', payerBank: 'Banesco', payerId: 'V-12345678'),
        ),
      );
      expect(paid.proof?.reference, '01029988');
      expect(paid.proof?.payerBank, 'Banesco');
      expect(paid.proof?.payerId, 'V-12345678');
      expect(paid.proof?.verified, isFalse);
    });

    test('el efectivo no pide referencia', () async {
      final paid = await repo.addPayment(pay(efectivoUsd));
      expect(paid.proof, isNull);
    });

    test('la misma referencia del mismo banco no se cobra dos veces, ni en la tienda', () async {
      await repo.addPayment(
        pay(
          pagoMovil,
          proof: const ProofInput(reference: '55443322', payerBank: 'Mercantil'),
        ),
      );
      await expectLater(
        repo.addPayment(
          pay(
            pagoMovil,
            proof: const ProofInput(reference: '55443322', payerBank: 'Mercantil'),
          ),
        ),
        throwsA(isA<GymException>().having((e) => e.message, 'mensaje', contains('ya está registrada'))),
      );
      final agua = (await repo.products()).firstWhere((p) => p.name.startsWith('Agua'));
      await expectLater(
        repo.registerSale(
          [CartLine(agua, 1)],
          pagoMovil,
          rate: rate,
          proof: const ProofInput(reference: '55443322', payerBank: 'Mercantil'),
        ),
        throwsA(isA<GymException>()),
      );
      // Otro banco, misma referencia: es otro pago.
      await repo.addPayment(
        pay(
          pagoMovil,
          proof: const ProofInput(reference: '55443322', payerBank: 'Banesco'),
        ),
      );
    });

    test('una referencia anulada se puede volver a usar', () async {
      final first = await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '11112222')));
      await repo.voidPayment(first.id, 'Error de plan');
      await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '11112222')));
    });

    test('foto del comprobante: quien cobró la adjunta y la cambia; los demás no', () async {
      repo.actAs(StaffRole.reception);
      final paid = await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '99990000')));
      final path = await repo.attachReceipt(ProofKind.payment, paid.id, Uint8List.fromList([1, 2, 3]));
      expect(path, startsWith('payments/${paid.id}/'));
      expect((await repo.payments()).firstWhere((p) => p.id == paid.id).proof?.receiptPath, path);
      expect(await repo.receiptImage(path), isA<MemoryImage>());
      await repo.attachReceipt(ProofKind.payment, paid.id, Uint8List.fromList([4, 5]));

      // Un cobro del dueño con foto: recepción no puede reemplazarla.
      repo.actAs(StaffRole.owner);
      final other = await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '99990001')));
      await repo.attachReceipt(ProofKind.payment, other.id, Uint8List.fromList([9]));
      repo.actAs(StaffRole.reception);
      await expectLater(repo.attachReceipt(ProofKind.payment, other.id, Uint8List.fromList([8])), throwsA(isA<GymException>()));
    });

    test('solo dueño y administrador verifican', () async {
      final paid = await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '77776666')));
      repo.actAs(StaffRole.reception);
      await expectLater(repo.setPaymentVerified(ProofKind.payment, paid.id, true), throwsA(isA<GymException>()));
      repo.actAs(StaffRole.admin);
      await repo.setPaymentVerified(ProofKind.payment, paid.id, true);
      expect((await repo.payments()).firstWhere((p) => p.id == paid.id).proof?.verified, isTrue);
      await repo.setPaymentVerified(ProofKind.payment, paid.id, false);
      expect((await repo.payments()).firstWhere((p) => p.id == paid.id).proof?.verified, isFalse);
    });

    test('el administrador cambia la foto que subió otro', () async {
      repo.actAs(StaffRole.reception);
      final paid = await repo.addPayment(pay(pagoMovil, proof: const ProofInput(reference: '31313131')));
      await repo.attachReceipt(ProofKind.payment, paid.id, Uint8List.fromList([1]));
      repo.actAs(StaffRole.admin);
      await repo.attachReceipt(ProofKind.payment, paid.id, Uint8List.fromList([2]));
    });

    test('en Ajustes se decide qué métodos piden referencia', () async {
      expect(pagoMovil.requiresReference, isTrue);
      await repo.setPaymentMethodRequiresReference('pago_movil', false);
      final updated = (await repo.paymentMethods()).firstWhere((m) => m.code == 'pago_movil');
      expect(updated.requiresReference, isFalse);
      await repo.addPayment(pay(updated));
      repo.actAs(StaffRole.reception);
      await expectLater(repo.setPaymentMethodRequiresReference('pago_movil', true), throwsA(isA<GymException>()));
    });
  });

  group('compras con método de pago', () {
    test('en bolívares guarda la tasa y el total en Bs.', () async {
      final methods = await repo.paymentMethods();
      final bs = methods.firstWhere((m) => m.code == 'efectivo_bs');
      final shaker = (await repo.products()).firstWhere((p) => p.name.startsWith('Shaker'));
      await expectLater(
        repo.registerPurchase(
          NewPurchase(
            lines: [PurchaseLine(product: shaker, quantity: 2, unitCostCents: 350)],
            purchasedOn: testNow,
            method: bs,
          ),
        ),
        throwsA(isA<GymException>()),
        reason: 'sin tasa no se registra en Bs.',
      );
      await repo.registerPurchase(
        NewPurchase(
          lines: [PurchaseLine(product: shaker, quantity: 2, unitCostCents: 350)],
          purchasedOn: testNow,
          method: bs,
          rate: rate,
          paymentReference: 'REC-1',
        ),
      );
      final p = (await repo.purchases()).first;
      expect(p.currency, Currency.ves);
      expect(p.totalVesCents, 560000); // $7 × 800
      expect(p.paymentReference, 'REC-1');
    });

    test('en dólares no lleva monto en Bs.', () async {
      final shaker = (await repo.products()).firstWhere((p) => p.name.startsWith('Shaker'));
      await repo.registerPurchase(
        NewPurchase(
          lines: [PurchaseLine(product: shaker, quantity: 1, unitCostCents: 350)],
          purchasedOn: testNow,
          method: efectivoUsd,
        ),
      );
      final p = (await repo.purchases()).first;
      expect(p.currency, Currency.usd);
      expect(p.totalVesCents, isNull);
      expect(p.methodName, efectivoUsd.name);
    });
  });

  group('pantallas', () {
    testWidgets('Pagos filtra los que faltan por verificar y abre el comprobante', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repo));
      await tester.pumpAndSettle();
      await goTo(tester, 'Pagos');
      final pending = (await repo.payments()).where((p) => !p.voided && p.proof?.reference != null && !p.proof!.verified).length;
      expect(pending, greaterThan(0));
      await tester.tap(find.text('Por verificar  $pending'));
      await tester.pumpAndSettle();
      expect(find.text('POR VERIFICAR'), findsNWidgets(pending));
      expect(find.text('VERIFICADO'), findsNothing);

      await tester.tap(find.text('POR VERIFICAR').first);
      await tester.pumpAndSettle();
      expect(find.text('COMPROBANTE'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Verificar pago'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(OutlinedButton, 'Quitar verificación'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('en una compra se crea un producto nuevo sin salir', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repo));
      await tester.pumpAndSettle();
      await goTo(tester, 'Compras');
      await tester.tap(find.widgetWithText(FilledButton, 'Nueva compra'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Crear producto nuevo'));
      await tester.pumpAndSettle();
      expect(find.text('PRODUCTO NUEVO'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre *'), 'Electrolitos 1 L');
      await tester.enterText(find.widgetWithText(TextFormField, 'Código (SKU)'), '7591234567890');
      await tester.enterText(find.widgetWithText(TextFormField, 'Precio de venta *'), '3,00');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear y usar'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Costo c/u'), '1,50');
      await tester.enterText(find.widgetWithText(TextFormField, 'Cant.'), '24');
      await tester.pumpAndSettle();
      final dialog = find.byType(FormDialog);
      await tester.ensureVisible(find.descendant(of: dialog, matching: find.text(r'Efectivo ($)')));
      await tester.tap(find.descendant(of: dialog, matching: find.text(r'Efectivo ($)')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, r'Registrar $36,00'));
      await tester.pumpAndSettle();

      final created = (await repo.products()).firstWhere((p) => p.name == 'Electrolitos 1 L');
      expect(created.sku, '7591234567890');
      expect(created.stock, 24);
      expect(created.costCents, 150);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el código de un producto se puede escanear', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repo));
      await tester.pumpAndSettle();
      await goTo(tester, 'Inventario');
      await tester.tap(find.widgetWithText(FilledButton, 'Nuevo producto'));
      await tester.pumpAndSettle();
      // En pruebas la plataforma es Android: hay cámara.
      expect(find.byTooltip('Escanear código'), findsOneWidget);
      // Un código repetido no se acepta.
      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre *'), 'Otro shaker');
      await tester.enterText(find.widgetWithText(TextFormField, 'Código (SKU)'), 'SHK-700');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ya es de Shaker'), findsOneWidget);
    });

    testWidgets('la tienda pide la referencia del pago móvil', (tester) async {
      useDesktopWindow(tester);
      await tester.pumpWidget(buildTestApp(repo: repo));
      await tester.pumpAndSettle();
      await goTo(tester, 'Tienda');
      await tester.tap(find.text('Agua mineral 600 ml').first);
      await tester.pumpAndSettle();
      final receipt = find.ancestor(of: find.text('VENTA EN CURSO'), matching: find.byType(Container)).first;
      await tester.tap(find.descendant(of: receipt, matching: find.text('Pago móvil')));
      await tester.pumpAndSettle();
      expect(find.text('COMPROBANTE · PAGO MÓVIL'), findsOneWidget);
      final charge = find.descendant(of: receipt, matching: find.byType(FilledButton)).last;
      expect(tester.widget<FilledButton>(charge).onPressed, isNull);
      await tester.enterText(find.widgetWithText(TextField, 'Referencia *'), '44556677');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(charge).onPressed, isNotNull);
      await tester.ensureVisible(charge);
      await tester.pumpAndSettle();
      await tester.tap(charge);
      await tester.pumpAndSettle();
      final sale = (await repo.sales()).firstWhere((s) => s.proof?.reference == '44556677');
      expect(sale.proof?.reference, '44556677');
      expect(sale.methodCode, 'pago_movil');
    });
  });
}
