// Hecho por Briann$ Workers Corp.
/// Genera los iconos de la PWA (web/icons, web/favicon.png), Android (mipmap)
/// e iOS (AppIcon) a partir del mismo dibujo del disco que usa la app
/// (PlatePainter):
///   flutter test test/generate_icons_test.dart --run-skipped
@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gimnasio_app/core/theme/app_theme.dart';
import 'package:gimnasio_app/core/widgets/plate_mark.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // (archivo, tamaño, margen del disco). "maskable": los lanzadores recortan
  // en círculo/squircle; el disco queda dentro de la zona segura del 80 %.
  final icons = [
    ('web/icons/Icon-192.png', 192, .06),
    ('web/icons/Icon-512.png', 512, .06),
    ('web/icons/Icon-maskable-192.png', 192, .17),
    ('web/icons/Icon-maskable-512.png', 512, .17),
    ('web/icons/apple-touch-icon.png', 180, .1),
    ('web/favicon.png', 48, .02),
    for (final (density, size) in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)])
      ('android/app/src/main/res/mipmap-$density/ic_launcher.png', size, .1),
    for (final (name, size) in [
      ('20x20@1x', 20), ('20x20@2x', 40), ('20x20@3x', 60),
      ('29x29@1x', 29), ('29x29@2x', 58), ('29x29@3x', 87),
      ('40x40@1x', 40), ('40x40@2x', 80), ('40x40@3x', 120),
      ('60x60@2x', 120), ('60x60@3x', 180),
      ('76x76@1x', 76), ('76x76@2x', 152), ('83.5x83.5@2x', 167),
      ('1024x1024@1x', 1024),
    ])
      ('ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-$name.png', size, .1),
  ];

  for (final (path, size, inset) in icons) {
    testWidgets(path, (tester) async {
      final key = GlobalKey();
      tester.view
        ..physicalSize = Size(size.toDouble(), size.toDouble())
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: SizedBox.square(
          dimension: size.toDouble(),
          child: ColoredBox(
            color: AppColors.bg,
            child: CustomPaint(painter: PlatePainter(color: AppColors.plateBlue, hole: AppColors.bg, inset: inset)),
          ),
        ),
      ));

      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      expect(File(path).existsSync(), isTrue);
    }, skip: true);
  }
}
