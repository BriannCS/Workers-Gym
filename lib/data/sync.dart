// Hecho por Briann$ Workers Corp.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gym_repository.dart';

enum SyncStatus {
  /// Modo demo: no hay backend, nada que sincronizar.
  local('Modo demo'),
  connecting('Conectando'),
  live('En vivo'),
  offline('Sin conexión');

  const SyncStatus(this.label);
  final String label;
}

/// Qué providers recargar cuando cambia cada tabla. `member_overview` es una
/// vista (no emite eventos), por eso pagos y planes también recargan clientes.
final Map<String, List<ProviderOrFamily>> _affected = {
  'members': [membersProvider],
  'plans': [plansProvider, membersProvider],
  'payments': [paymentsProvider, memberPaymentsProvider, membersProvider, cashDayProvider],
  'attendance': [todayAttendanceProvider],
  'suppliers': [suppliersProvider, productsProvider],
  'products': [productsProvider],
  'sales': [salesProvider, cashDayProvider],
  'purchases': [purchasesProvider, productsProvider],
  'payment_methods': [paymentMethodsProvider],
  'settings': [settingsProvider],
  'workout_logs': [workoutsProvider],
  // Un cambio de rol, permiso o suspensión se aplica al instante en la app.
  'staff': [currentStaffProvider, staffDirectoryProvider],
  'role_permissions': [currentStaffProvider, rolePermissionsProvider],
  'staff_time_entries': [staffTimeEntriesProvider, staffDirectoryProvider],
};

/// Mantiene un canal de Supabase Realtime abierto y recarga solo lo afectado
/// cuando otro dispositivo (PC de recepción, teléfono) escribe. Al reconectar o
/// volver de segundo plano recarga todo, porque pudo perder eventos.
class SyncController extends Notifier<SyncStatus> {
  RealtimeChannel? _channel;
  Timer? _debounce;
  final _pending = <String>{};
  bool _wasLive = false;

  /// Un corte breve del socket (se reconecta solo) no debe hacer parpadear el
  /// indicador: si estaba en vivo, se espera un poco antes de mostrarlo.
  Timer? _grace;
  static const _graceDelay = Duration(seconds: 4);

  void _show(SyncStatus next) {
    if (next == SyncStatus.live || stateOrNull != SyncStatus.live) {
      _grace?.cancel();
      _grace = null;
      state = next;
      return;
    }
    _grace ??= Timer(_graceDelay, () {
      _grace = null;
      state = next;
    });
  }

  @override
  SyncStatus build() {
    final db = ref.watch(supabaseClientProvider);
    if (db == null) return SyncStatus.local;
    // Solo con sesión: el canal usa el token del usuario para aplicar RLS.
    // Se observa SOLO quién es (no sus datos): si observara todo el acceso,
    // cada recarga de la sesión (que este mismo canal provoca al conectar)
    // reconstruiría el canal y la app oscilaría entre "En vivo" y "Conectando".
    if (ref.watch(currentStaffProvider.select((a) => a.value?.userId)) == null) return SyncStatus.connecting;

    final channel = db.channel('gym-sync');
    for (final table in _affected.keys) {
      channel.onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: table, callback: (_) => _queue(table));
    }
    channel.subscribe((status, _) {
      // Avisos de un canal ya reemplazado no cuentan.
      if (!identical(_channel, channel)) return;
      final live = status == RealtimeSubscribeStatus.subscribed;
      if (live && !_wasLive && stateOrNull != null) refreshAll();
      _wasLive = live;
      _show(switch (status) {
        RealtimeSubscribeStatus.subscribed => SyncStatus.live,
        RealtimeSubscribeStatus.timedOut || RealtimeSubscribeStatus.channelError => SyncStatus.offline,
        RealtimeSubscribeStatus.closed => SyncStatus.connecting,
      });
    });
    _channel = channel;

    // Volver de segundo plano (pestaña oculta, teléfono bloqueado) = posible
    // socket caído y eventos perdidos.
    final lifecycle = AppLifecycleListener(onResume: refreshAll);

    ref.onDispose(() {
      lifecycle.dispose();
      _debounce?.cancel();
      _grace?.cancel();
      _grace = null;
      final old = _channel;
      _channel = null;
      if (old != null) db.removeChannel(old);
    });
    return SyncStatus.connecting;
  }

  /// Agrupa ráfagas de eventos (una venta toca varias filas) en una recarga.
  void _queue(String table) {
    _pending.add(table);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      final providers = {for (final t in _pending) ...?_affected[t]};
      _pending.clear();
      for (final p in providers) {
        ref.invalidate(p);
      }
    });
  }

  void refreshAll() {
    for (final p in {for (final list in _affected.values) ...list}) {
      ref.invalidate(p);
    }
  }
}

final syncStatusProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
