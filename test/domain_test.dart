// Hecho por Briann$ Workers Corp.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:gimnasio_app/core/formatters.dart';
import 'package:gimnasio_app/core/input_formatters.dart';
import 'package:gimnasio_app/data/rates.dart';
import 'package:gimnasio_app/domain/models.dart';

void main() {
  final today = DateTime(2026, 9, 28, 10, 30);

  group('membershipStatus', () {
    test('sin pagos', () => expect(membershipStatus(null, today), MembershipStatus.none));

    test('venció ayer aunque hayan pasado pocas horas', () {
      // Bug del prototipo original: inDays truncaba -0.4 a 0 y lo marcaba "próximo".
      expect(membershipStatus(DateTime(2026, 9, 27), today), MembershipStatus.expired);
    });

    test('vence hoy o dentro de $expiringSoonDays días: por vencer', () {
      expect(membershipStatus(DateTime(2026, 9, 28), today), MembershipStatus.expiringSoon);
      expect(membershipStatus(DateTime(2026, 10, 1), today), MembershipStatus.expiringSoon);
    });

    test('más de $expiringSoonDays días: solvente', () {
      expect(membershipStatus(DateTime(2026, 10, 2), today), MembershipStatus.active);
    });

    test('la hora del día no altera la cuenta', () {
      expect(daysLeft(DateTime(2026, 9, 29, 0, 1), DateTime(2026, 9, 28, 23, 59)), 1);
    });
  });

  group('renewalPeriod', () {
    test('sin membresía previa empieza hoy', () {
      final p = renewalPeriod(currentExpiresOn: null, today: today, durationDays: 30);
      expect(p.start, DateTime.utc(2026, 9, 28));
      expect(p.end, DateTime.utc(2026, 10, 27));
    });

    test('vigente: continúa desde el día siguiente al vencimiento', () {
      final p = renewalPeriod(currentExpiresOn: DateTime(2026, 10, 5), today: today, durationDays: 30);
      expect(p.start, DateTime.utc(2026, 10, 6));
      expect(p.end, DateTime.utc(2026, 11, 4));
    });

    test('vence hoy: el nuevo periodo empieza mañana', () {
      final p = renewalPeriod(currentExpiresOn: DateTime(2026, 9, 28), today: today, durationDays: 1);
      expect(p.start, DateTime.utc(2026, 9, 29));
      expect(p.end, DateTime.utc(2026, 9, 29));
    });

    test('vencida: no cobra los días perdidos, empieza hoy', () {
      final p = renewalPeriod(currentExpiresOn: DateTime(2026, 9, 1), today: today, durationDays: 90);
      expect(p.start, DateTime.utc(2026, 9, 28));
      expect(p.end, DateTime.utc(2026, 12, 26));
    });
  });

  group('parseMoney', () {
    for (final (input, cents) in [
      ('30', 3000),
      ('30,5', 3050),
      ('30.50', 3050),
      (r'$ 1.234,56', 123456),
      ('0', 0),
    ]) {
      test(input, () => expect(parseMoney(input), cents));
    }
    for (final bad in ['', 'abc', '-5']) {
      test('rechaza "$bad"', () => expect(parseMoney(bad), isNull));
    }
  });

  group('CashSummary', () {
    const rate = ExchangeRate(RateSource.bcvUsd, 800);
    Payment payment(int cents, PaymentMethod m, {bool voided = false}) => Payment(
          id: '$cents',
          memberId: 'm',
          memberName: 'M',
          planId: 'p',
          planName: 'P',
          amountCents: cents,
          methodCode: m.code,
          methodName: m.name,
          periodStart: today,
          periodEnd: today,
          paidAt: today,
          currency: m.currency,
          rate: m.inBolivares ? rate.value : null,
          amountVesCents: m.inBolivares ? rate.vesCents(cents) : null,
          voidedAt: voided ? today : null,
          voidReason: voided ? 'error' : null,
        );
    Sale sale(int cents, PaymentMethod m, {bool voided = false}) => Sale(
          id: 's$cents',
          methodCode: m.code,
          methodName: m.name,
          totalCents: cents,
          soldAt: today,
          items: const [],
          currency: m.currency,
          totalVesCents: m.inBolivares ? rate.vesCents(cents) : null,
          voidedAt: voided ? today : null,
          voidReason: voided ? 'error' : null,
        );
    const cash = PaymentMethod(code: 'efectivo_usd', name: r'Efectivo ($)', currency: Currency.usd);
    const zelle = PaymentMethod(code: 'zelle', name: 'Zelle', currency: Currency.usd);
    const movil = PaymentMethod(code: 'pago_movil', name: 'Pago móvil', currency: Currency.ves);

    test('suma por método en su moneda y excluye anulaciones', () {
      final s = CashSummary.of(
        [payment(3000, cash), payment(8000, zelle), payment(3000, movil), payment(3000, cash, voided: true)],
        [sale(250, cash), sale(500, movil), sale(400, zelle, voided: true)],
      );
      expect(s.membershipCents, 14000);
      expect(s.storeCents, 750);
      expect(s.totalCents, 14750);
      expect(s.byMethod['efectivo_usd']!.usdCents, 3250);
      expect(s.byMethod['zelle']!.usdCents, 8000);
      // Pago móvil: $30 + $5 a 800 Bs/$ = Bs. 28.000
      expect(s.byMethod['pago_movil']!.usdCents, 3500);
      expect(s.byMethod['pago_movil']!.vesCents, 2800000);
      expect(s.totalVesCents, 2800000);
      expect(s.voidedCount, 2);
      expect(s.voidedCents, 3400);
    });

    test('día sin movimientos', () {
      final s = CashSummary.of(const [], const []);
      expect(s.totalCents, 0);
      expect(s.voidedCount, 0);
    });
  });

  test('carrito y stock bajo', () {
    const agua = Product(id: 'a', name: 'Agua', priceCents: 100, costCents: 45, stock: 3, minStock: 3);
    const barra = Product(id: 'b', name: 'Barra', priceCents: 300, costCents: 170, stock: 10, minStock: 2);
    expect(cartTotal(const [CartLine(agua, 2), CartLine(barra, 1)]), 500);
    expect(agua.lowStock, isTrue); // en el mínimo cuenta como bajo
    expect(barra.lowStock, isFalse);
  });

  test('Member.matches busca por nombre y por dígitos de cédula o teléfono', () {
    final m = Member(id: '1', fullName: 'María Rojas', documentId: 'V-24518330', phone: '04145550192', createdAt: today);
    expect(m.matches('maría'), isTrue);
    expect(m.matches('24.518'), isTrue); // con puntos, como se ve en pantalla
    expect(m.matches('24518330'), isTrue);
    expect(m.matches('0414-555'), isTrue); // con guion, como se ve en pantalla
    expect(m.matches('pedro'), isFalse);
    expect(m.initials, 'MR');
  });

  group('formato de cédula y teléfono', () {
    test('cédula con puntos de miles', () {
      expect(formatDocument('V-24518330'), 'V-24.518.330');
      expect(formatDocument('E-8109355'), 'E-8.109.355');
      expect(formatDocument(null), '—');
    });
    test('teléfono 0414-555-0192 y número de WhatsApp', () {
      expect(formatPhone('04145550192'), '0414-555-0192');
      expect(whatsappNumber('04145550192'), '584145550192');
      expect(whatsappNumber('123'), isNull);
    });
  });

  group('filtros de escritura', () {
    TextEditingValue type(TextInputFormatter f, String before, String after) =>
        f.formatEditUpdate(TextEditingValue(text: before), TextEditingValue(text: after));

    test('montos: solo números y un separador, máx. 2 decimales', () {
      const f = MoneyInputFormatter();
      expect(type(f, '', '30').text, '30');
      expect(type(f, '30', '30,5').text, '30,5');
      expect(type(f, '30,5', '30,55').text, '30,55');
      expect(type(f, '30,55', '30,555').text, '30,55'); // tercer decimal rechazado
      expect(type(f, '30', '30a').text, '30'); // letra rechazada
      expect(type(f, '30', r'30$').text, '30'); // símbolo rechazado
      expect(type(f, '3.5', '3.5.').text, '3.5'); // segundo separador rechazado
    });

    test('cédula: solo dígitos con puntos, letras fuera', () {
      const f = ThousandsInputFormatter();
      expect(type(f, '', '24518330').text, '24.518.330');
      expect(type(f, '', 'V24abc518').text, '24.518');
      expect(type(f, '', '1234567890').text, '123.456.789'); // máx. 9 dígitos
    });

    test('teléfono: solo dígitos con formato 0414-555-0192', () {
      const f = PhoneInputFormatter();
      expect(type(f, '', '04145550192').text, '0414-555-0192');
      expect(type(f, '', '0414abc555').text, '0414-555');
      expect(type(f, '', '+58 414 555 0192 99').text, '5841-455-5019'); // máx. 11 dígitos
    });
  });

  group('tasa de cambio', () {
    test('respuesta de ve.dolarapi.com: promedio, si no venta, si no compra', () {
      final r = parseDolarApi(RateSource.bcvUsd, {
        'promedio': 876.7976,
        'compra': null,
        'venta': null,
        'fechaActualizacion': '2026-10-13T00:00:00-04:00',
      })!;
      expect(r.value, 876.7976);
      expect(r.updatedAt, isNotNull);
      expect(parseDolarApi(RateSource.paralelo, {'promedio': null, 'venta': 1010.5})!.value, 1010.5);
      expect(parseDolarApi(RateSource.bcvEur, {'promedio': 0}), isNull);
      // Respuestas manipuladas de la API externa no se aceptan.
      expect(parseDolarApi(RateSource.bcvUsd, {'promedio': 'Infinity'}), isNull);
      expect(parseDolarApi(RateSource.bcvUsd, {'promedio': 'NaN'}), isNull);
      expect(parseDolarApi(RateSource.bcvUsd, {'promedio': 5e9}), isNull);
    });

    test('la tasa vigente sale de los ajustes', () {
      const fetched = {RateSource.bcvUsd: ExchangeRate(RateSource.bcvUsd, 800), RateSource.bcvEur: ExchangeRate(RateSource.bcvEur, 900)};
      expect(effectiveRate(const GymSettings(), fetched)!.value, 800);
      expect(effectiveRate(const GymSettings(rateSource: RateSource.bcvEur), fetched)!.value, 900);
      expect(effectiveRate(const GymSettings(rateSource: RateSource.paralelo), fetched), isNull); // no consultada
      expect(effectiveRate(const GymSettings(rateSource: RateSource.manual, manualRate: 950), const {})!.value, 950);
    });

    test(r'convierte centavos de dólar a centavos de bolívar', () {
      expect(const ExchangeRate(RateSource.bcvUsd, 876.80).vesCents(3000), 2630400); // $30 → Bs. 26.304,00
    });

    test('código estable para métodos nuevos', () {
      expect(methodCodeFor('Pago móvil BDV'), 'pago_movil_bdv');
      expect(methodCodeFor('  Zelle  '), 'zelle');
    });
  });
}
