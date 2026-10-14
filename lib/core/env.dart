// Hecho por Briann$ Workers Corp.
/// Configuración inyectada al compilar:
/// `flutter run --dart-define-from-file=env.json` (ver env.example.json).
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const gymName = String.fromEnvironment('GYM_NAME', defaultValue: 'Workers Gym');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
