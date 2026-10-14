// Hecho por Briann$ Workers Corp.
import 'dart:ui' show PlatformDispatcher, Brightness;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias locales del dispositivo. Se sobrescribe en `main`; null en
/// tests (el modo no se guarda).
final sharedPrefsProvider = Provider<SharedPreferences?>((ref) => null);

const _key = 'theme_dark';

/// Modo oscuro (true) o claro (false). Es una preferencia de cada
/// dispositivo: la PC de recepción y el teléfono pueden usar modos distintos.
/// La primera vez sigue el modo del sistema.
class ThemeModeController extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(sharedPrefsProvider)?.getBool(_key) ??
      PlatformDispatcher.instance.platformBrightness == Brightness.dark;

  void toggle() {
    state = !state;
    ref.read(sharedPrefsProvider)?.setBool(_key, state);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, bool>(ThemeModeController.new);
