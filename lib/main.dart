// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/env.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'data/demo_gym_repository.dart';
import 'data/gym_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  Intl.defaultLocale = 'es';
  final prefs = await SharedPreferences.getInstance();

  final SupabaseClient? supabase;
  if (Env.hasSupabase) {
    await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseKey);
    supabase = Supabase.instance.client;
  } else {
    supabase = null;
  }

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      supabaseClientProvider.overrideWithValue(supabase),
      gymRepositoryProvider.overrideWithValue(
        supabase == null ? DemoGymRepository.seeded() : SupabaseGymRepository(supabase),
      ),
    ],
    child: const GymApp(),
  ));
}

class GymApp extends ConsumerWidget {
  const GymApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = ref.watch(themeModeProvider);
    return MaterialApp.router(
      // Los colores se resuelven al pintar según el modo (ver ModeColor): al
      // cambiarlo se remonta el árbol para repintar todo. Router y datos viven
      // en providers, así que se conserva la pantalla actual.
      key: ValueKey(dark),
      title: Env.gymName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(dark: dark),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
