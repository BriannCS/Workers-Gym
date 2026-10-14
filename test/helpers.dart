// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/data/demo_gym_repository.dart';
import 'package:gimnasio_app/data/gym_repository.dart';
import 'package:gimnasio_app/data/rates.dart';
import 'package:gimnasio_app/domain/models.dart';
import 'package:gimnasio_app/main.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:material_ui/material_ui.dart';

/// Fecha fija para que los datos demo y los estados sean deterministas.
final testNow = DateTime(2026, 9, 28, 17, 30);

Future<void> initTestLocale() => initializeDateFormatting('es');

/// Tasas fijas: los tests nunca llaman a ve.dolarapi.com.
const testRates = {
  RateSource.bcvUsd: ExchangeRate(RateSource.bcvUsd, 800),
  RateSource.bcvEur: ExchangeRate(RateSource.bcvEur, 900),
  RateSource.paralelo: ExchangeRate(RateSource.paralelo, 1000),
};

Widget buildTestApp({DemoGymRepository? repo}) => ProviderScope(
      overrides: [
        gymRepositoryProvider.overrideWithValue(repo ?? DemoGymRepository.seeded(clock: () => testNow)),
        clockProvider.overrideWithValue(() => testNow),
        exchangeRatesProvider.overrideWith((ref) async => testRates),
      ],
      child: const GymApp(),
    );

/// Métodos de ejemplo del repositorio demo.
const cashUsd = PaymentMethod(code: 'efectivo_usd', name: r'Efectivo ($)', currency: Currency.usd);
const pagoMovil = PaymentMethod(code: 'pago_movil', name: 'Pago móvil', currency: Currency.ves);

/// Ventana de escritorio típica de recepción.
void useDesktopWindow(WidgetTester tester, {Size size = const Size(1440, 900)}) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

const phoneSize = Size(390, 844); // iPhone 14 / Android mediano
const tabletSize = Size(900, 1180);

/// Navega como lo haría una persona en cualquier tamaño: pestaña con texto
/// (escritorio), pestaña con solo icono (tableta) o barra inferior / "Más"
/// (teléfono).
Future<void> goTo(WidgetTester tester, String section) async {
  var target = find.text(section.toUpperCase());
  if (target.evaluate().isEmpty) target = find.byTooltip(section);
  if (target.evaluate().isEmpty) {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    target = find.text(section.toUpperCase());
  }
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}
