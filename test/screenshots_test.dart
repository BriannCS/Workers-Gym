// Hecho por Briann$ Workers Corp.
/// Genera capturas PNG de cada pantalla con las fuentes reales para revisar
/// el diseño sin abrir la app:
///   flutter test test/screenshots_test.dart --run-skipped --update-goldens
/// Salida en test/screenshots/.
@Tags(['screenshots'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'helpers.dart';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
  }
  await loader.load();
}

void main() {
  setUpAll(() async {
    await initTestLocale();
    await _loadFont('Archivo', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Archivo-$w.ttf']);
    await _loadFont('BigShoulders', [for (final w in [700, 800]) 'assets/fonts/BigShoulders-$w.ttf']);
    await _loadFont('PlexMono', [for (final w in [400, 500, 600]) 'assets/fonts/PlexMono-$w.ttf']);
    final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
    await _loadFont('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  });

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screenshots/$name.png'));
  }

  testWidgets('capturas', (tester) async {
    useDesktopWindow(tester);
    await tester.pumpWidget(buildTestApp());
    await shot(tester, '01_inicio');

    await goTo(tester, 'Asistencia');
    await tester.enterText(find.byType(TextField), 'an');
    await shot(tester, '02_asistencia');

    await goTo(tester, 'Clientes');
    await shot(tester, '03_clientes');

    await tester.tap(find.widgetWithText(FilledButton, 'Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Cédula'), '28123456');
    await tester.enterText(find.widgetWithText(TextFormField, 'Teléfono'), '04241234567');
    await shot(tester, '04_nuevo_cliente');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Luis Alberto Méndez'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Luis Alberto Méndez'));
    await shot(tester, '05_detalle_cliente');
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar pago'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pago móvil'));
    await shot(tester, '06_cobro_en_bolivares');
    for (var i = 0; i < 2; i++) {
      await tester.tapAt(const Offset(5, 5)); // cierra pago y luego detalle
      await tester.pumpAndSettle();
    }

    await goTo(tester, 'Pagos');
    await shot(tester, '07_pagos');

    await goTo(tester, 'Tienda');
    await tester.tap(find.text('Agua mineral 600 ml'));
    await tester.tap(find.text('Barra de proteína'));
    await shot(tester, '08_tienda');

    await goTo(tester, 'Inventario');
    await shot(tester, '09_inventario');

    await goTo(tester, 'Compras');
    await shot(tester, '10_compras');
    await tester.tap(find.widgetWithText(FilledButton, 'Nueva compra'));
    await shot(tester, '11_nueva_compra');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await goTo(tester, 'Caja');
    await shot(tester, '12_caja');
    await tester.tap(find.text('Bebida isotónica, Barra de proteína'));
    await shot(tester, '13_detalle_movimiento');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await goTo(tester, 'Ajustes');
    await shot(tester, '14_ajustes');

    // Modo oscuro
    await tester.tap(find.byTooltip('Modo oscuro'));
    await shot(tester, '15_ajustes_oscuro');
    await goTo(tester, 'Inicio');
    await shot(tester, '16_inicio_oscuro');
    await goTo(tester, 'Tienda');
    await shot(tester, '17_tienda_oscuro');
    await goTo(tester, 'Caja');
    await shot(tester, '18_caja_oscuro');
    await tester.tap(find.byTooltip('Modo claro'));
    await tester.pumpAndSettle();
  }, skip: true);

  testWidgets('capturas teléfono', (tester) async {
    useDesktopWindow(tester, size: phoneSize);
    await tester.pumpWidget(buildTestApp());
    await shot(tester, 'm1_inicio');

    await goTo(tester, 'Clientes');
    await shot(tester, 'm2_clientes');

    await goTo(tester, 'Tienda');
    await tester.tap(find.text('Agua mineral 600 ml'));
    await tester.tap(find.text('Bebida isotónica'));
    await shot(tester, 'm3_tienda');

    await tester.tap(find.byIcon(Icons.more_horiz));
    await shot(tester, 'm4_menu_mas');
    await tester.tap(find.text('CAJA'));
    await shot(tester, 'm5_caja');

    await tester.tap(find.byTooltip('Modo oscuro'));
    await shot(tester, 'm6_caja_oscuro');
    await goTo(tester, 'Ajustes');
    await shot(tester, 'm7_ajustes_oscuro');
    await tester.tap(find.byTooltip('Modo claro'));
    await tester.pumpAndSettle();
  }, skip: true);
}
