// Hecho por Briann$ Workers Corp.
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Marca del gimnasio: un disco olímpico de 20 kg visto de frente (aro,
/// ranuras de agarre y el agujero de la barra). También genera los iconos de
/// la PWA, así que la marca y el icono instalado son el mismo dibujo.
class PlateMark extends StatelessWidget {
  const PlateMark({super.key, this.size = 40, this.color = AppColors.plateBlue, this.hole = AppColors.bg});

  final double size;
  final Color color;
  final Color hole;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: PlatePainter(color: color, hole: hole)));
}

class PlatePainter extends CustomPainter {
  const PlatePainter({required this.color, required this.hole, this.inset = 0});

  final Color color;
  final Color hole;

  /// Margen proporcional (0–0.5), útil para iconos "maskable".
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 * (1 - inset * 2);
    final darker = Color.lerp(color, Colors.black, .28)!;

    canvas.drawCircle(c, r, Paint()..color = color);
    // Aro exterior en relieve.
    canvas.drawCircle(c, r * .86, Paint()
      ..color = darker
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .05);
    // Tres ranuras de agarre.
    final grip = Paint()
      ..color = darker
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * .11;
    for (var i = 0; i < 3; i++) {
      final a = -math.pi / 2 + i * 2 * math.pi / 3;
      canvas.drawArc(Rect.fromCircle(center: c, radius: r * .62), a - .38, .76, false, grip);
    }
    // Buje y agujero de la barra.
    canvas.drawCircle(c, r * .3, Paint()..color = darker);
    canvas.drawCircle(c, r * .17, Paint()..color = hole);
  }

  @override
  bool shouldRepaint(PlatePainter old) => old.color != color || old.hole != hole || old.inset != inset;
}
