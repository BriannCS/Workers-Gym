// Hecho por Briann$ Workers Corp.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/gym_repository.dart';
import '../../features/attendance/attendance_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/cash/cash_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/inventory/inventory_screen.dart';
import '../../features/members/members_screen.dart';
import '../../features/payments/payments_screen.dart';
import '../../features/plans/plans_screen.dart';
import '../../features/purchases/purchases_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/store/store_screen.dart';
import '../theme/theme_mode.dart';
import '../widgets/app_shell.dart';

/// Secciones de la app, en orden (el número de pestaña sale del índice).
/// [onPhoneBar]: va en la barra inferior del teléfono; el resto, en "Más".
enum AppSection {
  dashboard('/', 'Inicio', Icons.space_dashboard_outlined, onPhoneBar: true),
  attendance('/asistencia', 'Asistencia', Icons.how_to_reg_outlined, onPhoneBar: true),
  members('/clientes', 'Clientes', Icons.group_outlined, onPhoneBar: true),
  payments('/pagos', 'Pagos', Icons.receipt_long_outlined),
  store('/tienda', 'Tienda', Icons.storefront_outlined, onPhoneBar: true),
  inventory('/inventario', 'Inventario', Icons.inventory_2_outlined),
  purchases('/compras', 'Compras', Icons.local_shipping_outlined),
  cash('/caja', 'Caja', Icons.point_of_sale_outlined),
  plans('/planes', 'Planes', Icons.style_outlined),
  settings('/ajustes', 'Ajustes', Icons.settings_outlined);

  const AppSection(this.path, this.label, this.icon, {this.onPhoneBar = false});
  final String path;
  final String label;
  final IconData icon;
  final bool onPhoneBar;

  Widget get screen => switch (this) {
        dashboard => const DashboardScreen(),
        attendance => const AttendanceScreen(),
        members => const MembersScreen(),
        payments => const PaymentsScreen(),
        store => const StoreScreen(),
        inventory => const InventoryScreen(),
        purchases => const PurchasesScreen(),
        cash => const CashScreen(),
        plans => const PlansScreen(),
        settings => const SettingsScreen(),
      };
}

/// Pantalla actual, para volver a ella cuando el router se recrea. Vive en un
/// provider (no en una variable global) para que cada app/test empiece en "/".
class _LocationMemory {
  String location = '/';
}

final _locationMemoryProvider = Provider<_LocationMemory>((ref) => _LocationMemory());

final routerProvider = Provider<GoRouter>((ref) {
  final memory = ref.read(_locationMemoryProvider);
  // Al cambiar de modo claro/oscuro se crea un router nuevo: así todo el árbol
  // (incluidos los navegadores, que go_router conserva con GlobalKeys) se
  // reconstruye y repinta con los colores del nuevo modo (ver ModeColor).
  ref.watch(themeModeProvider);
  final supabase = ref.watch(supabaseClientProvider);
  final authChanges = supabase == null ? null : _StreamListenable(supabase.auth.onAuthStateChange);

  late final GoRouter router;
  void remember() => memory.location = router.routerDelegate.currentConfiguration.uri.toString();
  router = GoRouter(
    initialLocation: memory.location,
    refreshListenable: authChanges,
    redirect: (context, state) {
      if (supabase == null) return state.matchedLocation == '/login' ? '/' : null;
      final signedIn = supabase.auth.currentSession != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
        routes: [
          for (final s in AppSection.values)
            GoRoute(path: s.path, pageBuilder: (_, _) => NoTransitionPage(child: s.screen)),
        ],
      ),
    ],
  );
  router.routerDelegate.addListener(remember);
  ref.onDispose(() {
    router.routerDelegate.removeListener(remember);
    authChanges?.dispose();
    router.dispose();
  });
  return router;
});

class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<Object?> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<Object?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
