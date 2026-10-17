// Hecho por Briann$ Workers Corp.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'gym_repository.dart';

/// Tasas Bs/USD y Bs/EUR desde ve.dolarapi.com (la misma fuente del Apps
/// Script "Visor de Cambios"). La API responde con CORS abierto, así que la
/// PWA la consulta directo, sin servidor intermedio.
class RatesClient {
  RatesClient([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;

  static const _base = 'https://ve.dolarapi.com/v1';
  static const _paths = {
    RateSource.bcvUsd: '/dolares/oficial',
    RateSource.bcvEur: '/euros/oficial',
    RateSource.paralelo: '/dolares/paralelo',
  };

  /// Consulta las tres en paralelo. Las que fallen simplemente no aparecen.
  Future<Map<RateSource, ExchangeRate>> fetch() async {
    final results = await Future.wait([for (final MapEntry(key: s, value: p) in _paths.entries) _one(s, p)]);
    return {for (final r in results.nonNulls) r.source: r};
  }

  Future<ExchangeRate?> _one(RateSource source, String path) async {
    try {
      final res = await _http.get(Uri.parse('$_base$path'), headers: {'Accept': 'application/json'}).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      return parseDolarApi(source, jsonDecode(res.body) as Map<String, dynamic>);
    } catch (_) {
      return null; // sin red o respuesta inválida
    }
  }
}

/// Igual que `parseCotizacion_` del Apps Script: promedio, si no venta, si no compra.
/// Descarta valores no finitos o absurdos (la API es externa: no se le cree todo;
/// el servidor aplica además su propio rango).
ExchangeRate? parseDolarApi(RateSource source, Map<String, dynamic> json) {
  final value = [json['promedio'], json['venta'], json['compra']]
      .map((v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}'))
      .firstWhere((v) => v != null && v.isFinite && v > 0 && v < 1000000, orElse: () => null);
  if (value == null) return null;
  final date = DateTime.tryParse('${json['fechaActualizacion'] ?? ''}')?.toLocal();
  return ExchangeRate(source, value, updatedAt: date);
}

final ratesClientProvider = Provider<RatesClient>((ref) => RatesClient());

/// Tasas consultadas. Se piden solo cuando una pantalla las necesita y se
/// renuevan cada 15 minutos (como `CACHE_SECONDS` del script).
final exchangeRatesProvider = FutureProvider<Map<RateSource, ExchangeRate>>((ref) async {
  final timer = Timer(const Duration(minutes: 15), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return ref.watch(ratesClientProvider).fetch();
});

/// Tasa con la que se cobra ahora según Ajustes. Null = no disponible
/// (sin conexión y sin tasa manual).
final currentRateProvider = FutureProvider<ExchangeRate?>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  if (settings.rateSource == RateSource.manual) return effectiveRate(settings, const {});
  return effectiveRate(settings, await ref.watch(exchangeRatesProvider.future));
});
