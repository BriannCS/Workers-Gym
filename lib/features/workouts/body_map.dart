// Hecho por Briann$ - Workers Corp.
// Silueta 2D (frente y espalda) con los músculos coloreados. Si se pasa
// [onTap], tocar un músculo lo marca o desmarca.
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/workouts.dart';

class BodyMap extends StatelessWidget {
  const BodyMap({super.key, required this.colors, this.onTap, this.height = 240, this.showLabels = true});

  /// Color de cada parte trabajada; las que no están se pintan neutras.
  final Map<BodyPart, Color> colors;
  final ValueChanged<BodyPart>? onTap;
  final double height;
  final bool showLabels;

  /// Mismo color para todas las partes dadas ("cuerpo completo" = todas).
  static Map<BodyPart, Color> highlight(Iterable<BodyPart> parts, Color color) {
    final set = parts.contains(BodyPart.cuerpoCompleto) ? BodyPart.specific : parts;
    return {for (final p in set) p: color};
  }

  static const _w = 100.0, _h = 210.0;

  @override
  Widget build(BuildContext context) {
    final viewW = height * _w / _h;
    Widget view(bool back, String label) {
      final painter = _BodyPainter(back: back, colors: colors);
      final canvas = SizedBox(
        width: viewW,
        height: height,
        child: CustomPaint(painter: painter),
      );
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          onTap == null
              ? canvas
              : MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (d) {
                      final p = painter.partAt(d.localPosition, Size(viewW, height));
                      if (p != null) onTap!(p);
                    },
                    child: canvas,
                  ),
                ),
          if (showLabels) ...[const SizedBox(height: 6), Text(label, style: AppText.label.copyWith(fontSize: 9.5))],
        ],
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, spacing: height * .08, children: [view(false, 'FRENTE'), view(true, 'ESPALDA')]);
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({required this.back, required this.colors});

  final bool back;
  final Map<BodyPart, Color> colors;

  static RRect _r(double l, double t, double r, double b, [double rad = 4]) => RRect.fromLTRBR(l, t, r, b, Radius.circular(rad));

  static Path _rr(double l, double t, double r, double b, [double rad = 4]) => Path()..addRRect(_r(l, t, r, b, rad));
  static Path _ov(double cx, double cy, double w, double h) =>
      Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));

  /// Partes del cuerpo en coordenadas 100 × 210, en orden de dibujo (la
  /// última gana al tocar). null = piel/articulaciones, no se marcan.
  List<(BodyPart?, Path)> get _shapes {
    final both = <(BodyPart?, Path)>[
      (null, _ov(50, 14, 18, 20)), // cabeza
      (null, _rr(45.5, 22, 54.5, 30, 2)), // cuello
      (null, _ov(20, 98, 9, 11)), (null, _ov(80, 98, 9, 11)), // manos
      (null, _rr(38, 138, 48, 147, 3)), (null, _rr(52, 138, 62, 147, 3)), // rodillas
      (null, _rr(37, 187, 48, 196, 3)), (null, _rr(52, 187, 63, 196, 3)), // pies
      (BodyPart.hombros, _ov(30, 36, 15, 13)), (BodyPart.hombros, _ov(70, 36, 15, 13)),
      (BodyPart.antebrazos, _rr(16.5, 66, 26.5, 92, 5)), (BodyPart.antebrazos, _rr(73.5, 66, 83.5, 92, 5)),
      (BodyPart.pantorrillas, _rr(38, 148, 48, 186, 5)), (BodyPart.pantorrillas, _rr(52, 148, 62, 186, 5)),
    ];
    if (!back) {
      return [
        ...both,
        (BodyPart.pecho, _rr(37, 30, 49.3, 47, 5)), (BodyPart.pecho, _rr(50.7, 30, 63, 47, 5)),
        (BodyPart.biceps, _rr(21, 43, 30, 64, 5)), (BodyPart.biceps, _rr(70, 43, 79, 64, 5)),
        (BodyPart.abdomen, _rr(40.5, 49, 59.5, 80, 4)),
        (null, _rr(39, 81, 61, 92, 4)), // cadera
        (BodyPart.cuadriceps, _rr(37, 93, 46.5, 137, 5)), (BodyPart.cuadriceps, _rr(53.5, 93, 63, 137, 5)),
        (BodyPart.aductores, _rr(46.8, 94, 49.6, 126, 2)), (BodyPart.aductores, _rr(50.4, 94, 53.2, 126, 2)),
      ];
    }
    final backPath = Path()
      ..moveTo(38, 29)
      ..lineTo(62, 29)
      ..lineTo(64, 44)
      ..lineTo(59.5, 62)
      ..lineTo(40.5, 62)
      ..lineTo(36, 44)
      ..close();
    return [
      ...both,
      (BodyPart.espalda, backPath),
      (BodyPart.triceps, _rr(21, 43, 30, 64, 5)),
      (BodyPart.triceps, _rr(70, 43, 79, 64, 5)),
      (BodyPart.lumbar, _rr(41, 63.5, 59, 80, 4)),
      (BodyPart.gluteos, _rr(38, 81, 49.6, 101, 7)),
      (BodyPart.gluteos, _rr(50.4, 81, 62, 101, 7)),
      (BodyPart.isquios, _rr(38, 102, 49, 137, 5)),
      (BodyPart.isquios, _rr(51, 102, 62, 137, 5)),
    ];
  }

  double _scale(Size s) => s.height / BodyMap._h;

  BodyPart? partAt(Offset pos, Size size) {
    final k = _scale(size);
    final p = Offset(pos.dx / k, pos.dy / k);
    for (final (part, path) in _shapes.reversed) {
      if (part != null && path.contains(p)) return part;
    }
    return null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(_scale(size));
    final skin = Paint()..color = AppColors.border;
    final muscle = Paint()..color = AppColors.raised;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9
      ..color = AppColors.borderStrong;
    for (final (part, path) in _shapes) {
      final fill = part == null ? skin : (colors[part] != null ? (Paint()..color = colors[part]!) : muscle);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(_BodyPainter old) => old.back != back || !_same(old.colors, colors);

  static bool _same(Map<BodyPart, Color> a, Map<BodyPart, Color> b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
