// Hecho por Briann$ Workers Corp.
import 'dart:ui' show ColorSpace;

import 'package:material_ui/material_ui.dart';

import '../../domain/models.dart';

/// Color con valor claro y oscuro que se resuelve al pintar según
/// [AppColors.isDark]. Así los tokens siguen siendo `const` (y los 280+ usos
/// no cambian) y el modo se alterna sin reescribir cada pantalla.
///
/// Funciona porque tanto el motor nativo como el web leen el color vía los
/// getters `a/r/g/b` (Paint.color → toARGB32). Al cambiar de modo se remonta
/// el árbol (ver `GymApp`) para que todo se vuelva a pintar.
class ModeColor extends Color {
  const ModeColor(this.light, this.dark) : super(light);

  final int light;
  final int dark;

  Color get _now => Color(AppColors.isDark ? dark : light);

  @override
  double get a => _now.a;
  @override
  double get r => _now.r;
  @override
  double get g => _now.g;
  @override
  double get b => _now.b;
  @override
  ColorSpace get colorSpace => ColorSpace.sRGB;
}

/// Sistema visual de Workers Gym: la recepción como el cuaderno de
/// entrenamiento de un gimnasio de verdad. Papel cálido y tinta (de día),
/// pizarra y tiza (de noche), líneas de cuaderno y los colores de los discos
/// olímpicos (azul 20 kg, rojo 25, amarillo 15, verde 10) como única paleta.
abstract final class AppColors {
  /// Modo activo. Lo fija `themeModeProvider` antes de reconstruir la app.
  static bool isDark = false;

  // Papel y tinta  /  pizarra y tiza
  static const bg = ModeColor(0xFFF2EEE5, 0xFF15130F);
  static const surface = ModeColor(0xFFFBF9F4, 0xFF1E1B16);
  static const raised = ModeColor(0xFFE9E3D6, 0xFF2A261F); // campos, hover
  static const border = ModeColor(0xFFD8CFBE, 0xFF39332A); // línea de cuaderno
  static const borderStrong = ModeColor(0xFFB4A890, 0xFF5C5345);
  static const text = ModeColor(0xFF17140F, 0xFFF0EBE0); // tinta / tiza
  static const textMuted = ModeColor(0xFF5E574C, 0xFFA89E8D); // ≥ 6:1 en ambos modos
  static const ink = text;

  /// Lomo del menú: siempre más oscuro que la página, en ambos modos.
  static const spine = ModeColor(0xFF17140F, 0xFF0B0A08);
  static const onSpine = ModeColor(0xFFFBF9F4, 0xFFF0EBE0);

  // Discos olímpicos (más luminosos de noche para conservar contraste)
  static const plateBlue = ModeColor(0xFF2348B0, 0xFF7B97F2); // 20 kg — marca
  static const plateRed = ModeColor(0xFFC23126, 0xFFEE6A5C); // 25 kg — vencido / error
  static const plateYellow = Color(0xFFF2C230); // 15 kg — relleno de aviso (igual)
  static const plateGreen = ModeColor(0xFF2F7A3E, 0xFF5FBE72); // 10 kg — al día

  static const accent = plateBlue;
  static const onAccent = surface;
  static const success = plateGreen;
  static const warning = ModeColor(0xFF8F5B0F, 0xFFE6AE45); // amarillo legible como texto
  static const danger = plateRed;
  static const info = ModeColor(0xFF1E6E74, 0xFF5BBAC0);

  static Color forStatus(MembershipStatus s) => switch (s) {
        MembershipStatus.active => success,
        MembershipStatus.expiringSoon => warning,
        MembershipStatus.expired => danger,
        MembershipStatus.none || MembershipStatus.inactive => textMuted,
      };
}

abstract final class AppTheme {
  static const radius = 4.0; // esquinas de papel cortado, no de app genérica
  static const bodyFont = 'Archivo';
  static const displayFont = 'BigShoulders';
  static const monoFont = 'PlexMono';

  /// Tema para el modo indicado. Fija [AppColors.isDark] primero porque los
  /// tokens se resuelven con ese valor.
  static ThemeData build({required bool dark}) {
    AppColors.isDark = dark;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.ink,
      onPrimary: AppColors.surface,
      secondary: AppColors.plateBlue,
      onSecondary: AppColors.surface,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerHighest: AppColors.raised,
      surfaceContainerHigh: AppColors.raised,
      surfaceContainer: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      error: AppColors.danger,
      onError: AppColors.surface,
    );
    final square = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    OutlineInputBorder line(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: c, width: w),
        );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 16);
    const buttonText = TextStyle(fontFamily: bodyFont, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .2);

    final base = ThemeData(useMaterial3: true, brightness: brightness, colorScheme: scheme, fontFamily: bodyFont);
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      splashFactory: InkRipple.splashFactory,
      textTheme: base.textTheme.apply(bodyColor: AppColors.text, displayColor: AppColors.text),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
      iconTheme: const IconThemeData(color: AppColors.textMuted, size: 20),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.plateBlue,
        selectionColor: AppColors.plateBlue.withValues(alpha: .2),
        selectionHandleColor: AppColors.plateBlue,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        floatingLabelStyle: const TextStyle(color: AppColors.plateBlue, fontWeight: FontWeight.w600),
        prefixIconColor: AppColors.textMuted,
        border: line(AppColors.borderStrong),
        enabledBorder: line(AppColors.borderStrong),
        focusedBorder: line(AppColors.ink, 2),
        errorBorder: line(AppColors.danger),
        focusedErrorBorder: line(AppColors.danger, 2),
        errorStyle: const TextStyle(color: AppColors.danger),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.surface,
          disabledBackgroundColor: AppColors.raised,
          disabledForegroundColor: AppColors.textMuted,
          padding: buttonPadding,
          textStyle: buttonText,
          shape: square,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          padding: buttonPadding,
          textStyle: buttonText,
          shape: square,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.plateBlue,
          textStyle: buttonText.copyWith(decoration: TextDecoration.underline, decorationThickness: 1.5),
          shape: square,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.ink,
          hoverColor: AppColors.raised,
          shape: square,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: AppColors.ink, width: 1.5),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.borderStrong,
      ),
      cardTheme: CardThemeData(color: AppColors.surface, elevation: 0, margin: EdgeInsets.zero, shape: square),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.ink,
        secondarySelectedColor: AppColors.ink,
        side: const BorderSide(color: AppColors.borderStrong),
        // El color cambia con el estado: tinta normal, papel cuando el chip
        // está marcado (fondo de tinta). Sin esto el texto marcado no se ve.
        labelStyle: TextStyle(
          fontFamily: bodyFont,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.surface : AppColors.text),
        ),
        secondaryLabelStyle: const TextStyle(fontFamily: bodyFont, fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.surface),
        checkmarkColor: AppColors.surface,
        shape: square,
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.text,
          selectedBackgroundColor: AppColors.ink,
          selectedForegroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.ink, width: 1.5),
          shape: square,
          textStyle: buttonText.copyWith(fontSize: 13),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.surface : AppColors.textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.plateGreen : AppColors.raised),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.borderStrong),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(2)),
        textStyle: const TextStyle(fontFamily: monoFont, color: AppColors.surface, fontSize: 11.5, letterSpacing: .3),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: bodyFont, color: AppColors.surface, fontSize: 14),
        shape: square,
        width: 460,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.ink, linearTrackColor: AppColors.raised),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.borderStrong.withValues(alpha: .9)),
        radius: const Radius.circular(2),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.ink,
        headerForegroundColor: AppColors.surface,
        shape: square,
      ),
    );
  }
}

/// Estilos de texto con nombre propio; evita repetir TextStyle sueltos.
abstract final class AppText {
  /// Rótulo de formulario impreso: mono, mayúsculas, espaciado.
  static const label = TextStyle(
    fontFamily: AppTheme.monoFont,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 1.2,
    color: AppColors.textMuted,
  );

  /// Cifras de marcador (Big Shoulders).
  static TextStyle score(double size, {Color color = AppColors.text}) => TextStyle(
        fontFamily: AppTheme.displayFont,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: .95,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Horas, montos y códigos: mono con cifras tabulares.
  static TextStyle mono({double size = 13, FontWeight weight = FontWeight.w500, Color color = AppColors.text}) => TextStyle(
        fontFamily: AppTheme.monoFont,
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  static const muted = TextStyle(color: AppColors.textMuted, fontSize: 13);
}

/// Anchos donde cambia la composición: teléfono / tableta / escritorio.
abstract final class Breakpoints {
  static const phone = 640.0;
  static const desktop = 1100.0;
}

extension LayoutContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;
  bool get isPhone => screenWidth < Breakpoints.phone;
  bool get isDesktop => screenWidth >= Breakpoints.desktop;
}
