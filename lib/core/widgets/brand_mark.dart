// Hecho por Briann$ - Workers Corp.
import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Firma que va en las partes esenciales de la app (acceso, menú, ajustes,
/// cierre de caja).
const brandSignature = r'Hecho por Briann$ - Workers Corp.';

/// Tinta del sello. El dorado funciona sobre fondo claro y oscuro; el blanco y
/// el carbón son para fondos que lo piden.
enum BrandTint {
  gold('dorado'),
  white('negativo-blanco'),
  carbon('positivo-carbon');

  const BrandTint(this.file);
  final String file;
}

/// Sello de Workers Gym (la "G." en doble anillo con su satélite), tomado tal
/// cual del kit de marca. Los PNG viven en assets/brand/.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.tint = BrandTint.gold});

  final double size;
  final BrandTint tint;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brand/sello_${tint.file}.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Workers Gym',
      );
}

/// Línea de firma en tipografía mono, discreta.
class BrandSignature extends StatelessWidget {
  const BrandSignature({super.key, this.color = AppColors.textMuted, this.size = 11});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      Text(brandSignature, textAlign: TextAlign.center, style: AppText.mono(size: size, color: color));
}
