// Hecho por Briann$ Workers Corp.
// Reglas que el repositorio demo comparte con las funciones SQL
// (register_payment, void_payment, register_sale, void_sale, add_stock).
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/data/demo_gym_repository.dart';
import 'package:gimnasio_app/domain/models.dart';

import 'helpers.dart';

void main() {
  late DemoGymRepository repo;
  setUp(() => repo = DemoGymRepository.seeded(clock: () => testNow));

  Future<Product> product(String name) async => (await repo.products()).firstWhere((p) => p.name == name);
  Future<Member> member(String prefix) async => (await repo.members()).firstWhere((m) => m.fullName.startsWith(prefix));

  group('ventas', () {
    test('descuentan stock y el total sale de los precios del catálogo', () async {
      final agua = await product('Agua mineral 600 ml');
      final barra = await product('Barra de proteína');
      await repo.registerSale([CartLine(agua, 2), CartLine(barra, 1)], cashUsd);

      expect((await product('Agua mineral 600 ml')).stock, agua.stock - 2);
      expect((await product('Barra de proteína')).stock, barra.stock - 1);
      expect((await repo.sales()).first.totalCents, 2 * 100 + 300);
    });

    test('si un producto no alcanza, no se vende nada', () async {
      final agua = await product('Agua mineral 600 ml');
      final creatina = await product('Creatina 300 g'); // stock 3
      final salesBefore = (await repo.sales()).length;

      await expectLater(
        repo.registerSale([CartLine(agua, 1), CartLine(creatina, 4)], cashUsd),
        throwsA(isA<GymException>().having((e) => e.message, 'message', contains('Stock insuficiente de Creatina'))),
      );
      expect((await product('Agua mineral 600 ml')).stock, agua.stock);
      expect((await repo.sales()).length, salesBefore);
    });

    test('la misma línea repetida se suma antes de validar stock', () async {
      final creatina = await product('Creatina 300 g'); // stock 3
      await expectLater(
        repo.registerSale([CartLine(creatina, 2), CartLine(creatina, 2)], cashUsd),
        throwsA(isA<GymException>()),
      );
    });

    test('anular devuelve el stock y exige motivo; no se anula dos veces', () async {
      final agua = await product('Agua mineral 600 ml');
      final id = await repo.registerSale([CartLine(agua, 3)], cashUsd);

      await expectLater(repo.voidSale(id, '  '), throwsA(isA<GymException>()));
      await repo.voidSale(id, 'Error de cobro');
      expect((await product('Agua mineral 600 ml')).stock, agua.stock);
      await expectLater(repo.voidSale(id, 'otra vez'), throwsA(isA<GymException>()));
    });
  });

  group('stock', () {
    test('entradas suman, ajustes restan y nunca queda negativo', () async {
      final shaker = await product('Shaker 700 ml'); // stock 0
      expect(await repo.addStock(shaker.id, 10, unitCostCents: 400, note: 'Stock inicial'), 10);
      expect((await product('Shaker 700 ml')).costCents, 400);
      expect(await repo.addStock(shaker.id, -3, note: 'dañados'), 7);
      await expectLater(repo.addStock(shaker.id, -8, note: 'x'), throwsA(isA<GymException>()));
      await expectLater(repo.addStock(shaker.id, 0, note: 'x'), throwsA(isA<GymException>()));
      // Sin motivo no hay ajuste (igual que en el servidor).
      await expectLater(repo.addStock(shaker.id, 1), throwsA(isA<GymException>()));
    });
  });

  group('pagos', () {
    test('anular un pago devuelve el vencimiento anterior', () async {
      final luis = await member('Luis'); // vencido hace 4 días
      final plans = await repo.plans();
      final monthly = plans.firstWhere((p) => p.name == 'Mensual');
      final before = luis.expiresOn;

      final paid = await repo.addPayment(
        NewPayment.renewal(member: luis, plan: monthly, method: cashUsd, today: testNow),
      );
      expect((await member('Luis')).status(testNow), MembershipStatus.active);

      await repo.voidPayment(paid.id, 'Cobrado al cliente equivocado');
      final after = await member('Luis');
      expect(after.expiresOn, before);
      expect(after.status(testNow), MembershipStatus.expired);
    });

    test('el periodo lo recalcula el repositorio, no la vista previa', () async {
      final maria = await member('María'); // vigente, vence en 21 días
      final monthly = (await repo.plans()).firstWhere((p) => p.name == 'Mensual');
      // Vista previa hecha con datos viejos (sin vencimiento).
      final stale = NewPayment.renewal(
        member: Member(id: maria.id, fullName: maria.fullName, createdAt: maria.createdAt),
        plan: monthly,
        method: cashUsd,
        today: testNow,
      );
      final paid = await repo.addPayment(stale);
      expect(paid.periodStart, maria.expiresOn!.add(const Duration(days: 1)));
    });

    test('no se cobra un plan archivado', () async {
      final luis = await member('Luis');
      final archived = (await repo.plans()).firstWhere((p) => !p.active);
      await expectLater(
        repo.addPayment(NewPayment.renewal(member: luis, plan: archived, method: cashUsd, today: testNow)),
        throwsA(isA<GymException>()),
      );
    });
  });

  group('cobro en bolívares', () {
    const rate = ExchangeRate(RateSource.bcvUsd, 800);

    test('guarda la tasa y el monto en Bs.', () async {
      final luis = await member('Luis');
      final monthly = (await repo.plans()).firstWhere((p) => p.name == 'Mensual');
      final paid = await repo.addPayment(NewPayment.renewal(member: luis, plan: monthly, method: pagoMovil, today: testNow, rate: rate));
      expect(paid.currency, Currency.ves);
      expect(paid.rate, 800);
      expect(paid.amountVesCents, 2400000); // $30 × 800 = Bs. 24.000
      expect(paid.amountCents, 3000); // el precio sigue en dólares
    });

    test('sin tasa no se puede cobrar en bolívares', () async {
      final luis = await member('Luis');
      final monthly = (await repo.plans()).firstWhere((p) => p.name == 'Mensual');
      await expectLater(
        repo.addPayment(NewPayment.renewal(member: luis, plan: monthly, method: pagoMovil, today: testNow)),
        throwsA(isA<GymException>()),
      );
    });

    test('venta en Bs. con el total convertido', () async {
      final agua = await product('Agua mineral 600 ml');
      await repo.registerSale([CartLine(agua, 2)], pagoMovil, rate: rate);
      final sale = (await repo.sales()).first;
      expect(sale.totalCents, 200);
      expect(sale.totalVesCents, 160000);
    });
  });

  group('métodos de pago y ajustes', () {
    test('agregar, quitar y restaurar un método', () async {
      await repo.addPaymentMethod('Pago móvil BDV', Currency.ves);
      var methods = await repo.paymentMethods();
      final bdv = methods.firstWhere((m) => m.name == 'Pago móvil BDV');
      expect(bdv.code, 'pago_movil_bdv');
      expect(bdv.inBolivares, isTrue);

      await repo.setPaymentMethodActive(bdv.code, false);
      methods = await repo.paymentMethods();
      expect(methods.firstWhere((m) => m.code == bdv.code).active, isFalse);

      // Un método quitado no se puede usar para cobrar.
      final agua = await product('Agua mineral 600 ml');
      await expectLater(
        repo.registerSale([CartLine(agua, 1)], bdv, rate: const ExchangeRate(RateSource.bcvUsd, 800)),
        throwsA(isA<GymException>()),
      );
      await repo.setPaymentMethodActive(bdv.code, true);
      expect((await repo.paymentMethods()).firstWhere((m) => m.code == bdv.code).active, isTrue);
    });

    test('tasa manual exige un valor', () async {
      await expectLater(repo.saveSettings(const GymSettings(rateSource: RateSource.manual)), throwsA(isA<GymException>()));
      await repo.saveSettings(const GymSettings(rateSource: RateSource.manual, manualRate: 950));
      expect((await repo.settings()).manualRate, 950);
    });
  });

  group('compras e inventario', () {
    test('stock = inicial ± ajustes + compras − ventas, siempre', () async {
      // Datos de ejemplo
      for (final p in await repo.products()) {
        expect(p.stock, repo.computedStock()[p.id], reason: p.name);
      }
      // Tras compra, venta, ajuste y anulaciones
      final agua = await product('Agua mineral 600 ml');
      final id = await repo.registerPurchase(NewPurchase(
        purchasedOn: testNow,
        lines: [PurchaseLine(product: agua, quantity: 24, unitCostCents: 50)],
      ));
      await repo.registerSale([CartLine(agua, 5)], cashUsd);
      await repo.addStock(agua.id, -2, note: 'rotas');
      final sales = await repo.sales();
      await repo.voidSale(sales.first.id, 'error');
      for (final p in await repo.products()) {
        expect(p.stock, repo.computedStock()[p.id], reason: p.name);
      }
      expect((await product('Agua mineral 600 ml')).stock, agua.stock + 24 - 2);
      expect((await product('Agua mineral 600 ml')).costCents, 50); // costo de la última compra
      expect((await repo.purchases()).first.id, id);
    });

    test('anular una compra retira el stock; si ya se vendió, no se puede', () async {
      final shaker = await product('Shaker 700 ml'); // stock 0
      final id = await repo.registerPurchase(NewPurchase(
        purchasedOn: testNow,
        lines: [PurchaseLine(product: shaker, quantity: 3, unitCostCents: 350)],
      ));
      await repo.registerSale([CartLine(await product('Shaker 700 ml'), 2)], cashUsd);
      await expectLater(
        repo.voidPurchase(id, 'factura duplicada'),
        throwsA(isA<GymException>().having((e) => e.message, 'message', contains('ya se vendieron unidades de Shaker'))),
      );
      expect((await product('Shaker 700 ml')).stock, 1); // nada cambió

      final id2 = await repo.registerPurchase(NewPurchase(
        purchasedOn: testNow,
        lines: [PurchaseLine(product: await product('Shaker 700 ml'), quantity: 4, unitCostCents: 350)],
      ));
      await repo.voidPurchase(id2, 'factura duplicada');
      expect((await product('Shaker 700 ml')).stock, 1);
      expect((await repo.purchases()).firstWhere((p) => p.id == id2).voided, isTrue);
    });
  });

  test('foto de perfil: poner y quitar', () async {
    final maria = await member('María');
    await repo.setMemberPhoto(maria, Uint8List.fromList([1, 2, 3]));
    var updated = await member('María');
    expect(updated.photoPath, isNotNull);
    expect((await repo.memberPhotos(await repo.members())).containsKey(maria.id), isTrue);
    await repo.removeMemberPhoto(updated);
    updated = await member('María');
    expect(updated.photoPath, isNull);
    expect((await repo.memberPhotos(await repo.members())).containsKey(maria.id), isFalse);
  });
}
