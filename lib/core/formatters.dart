// Hecho por Briann$ Workers Corp.
import 'package:intl/intl.dart';

const currencySymbol = r'$';

final _money = NumberFormat('#,##0.00', 'es');

String formatMoney(int cents) => '$currencySymbol${_money.format(cents / 100)}';

/// Convierte lo que escribe el usuario ("30", "30,5", "1.234,50", "30.50")
/// a centavos. Devuelve null si no es un monto válido.
int? parseMoney(String input) {
  var s = input.trim().replaceAll(currencySymbol, '').replaceAll(' ', '');
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  final v = double.tryParse(s);
  if (v == null || v < 0) return null;
  return (v * 100).round();
}

String formatDate(DateTime d) => DateFormat('d MMM y', 'es').format(d);
String formatShortDate(DateTime d) => DateFormat('d MMM', 'es').format(d);
String formatTime(DateTime d) => DateFormat('HH:mm', 'es').format(d);
String formatLongDate(DateTime d) => toBeginningOfSentenceCase(DateFormat("EEEE, d 'de' MMMM", 'es').format(d));

/// "vence hoy", "en 5 días", "hace 3 días".
String relativeDays(int days) => switch (days) {
      0 => 'vence hoy',
      1 => 'vence mañana',
      -1 => 'venció ayer',
      > 1 => 'en $days días',
      _ => 'hace ${-days} días',
    };

String formatVes(int cents) => 'Bs. ${_money.format(cents / 100)}';

/// Tasa Bs/unidad: "876,80".
String formatRate(double rate) => NumberFormat('#,##0.00', 'es').format(rate);

final _thousands = NumberFormat('#,###', 'es');

/// "V-24518330" → "V-24.518.330".
String formatDocument(String? doc) {
  if (doc == null || doc.isEmpty) return '—';
  final dash = doc.indexOf('-');
  final prefix = dash > 0 ? doc.substring(0, dash + 1) : '';
  final digits = doc.replaceAll(RegExp(r'\D'), '');
  return digits.isEmpty ? doc : '$prefix${_thousands.format(int.parse(digits))}';
}

/// "04145550192" → "0414-555-0192".
String formatPhone(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '—';
  if (d.length == 11) return '${d.substring(0, 4)}-${d.substring(4, 7)}-${d.substring(7)}';
  return d;
}

/// Número para wa.me: "04145550192" → "584145550192".
String? whatsappNumber(String? phone) {
  final d = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (d.length == 11 && d.startsWith('0')) return '58${d.substring(1)}';
  return d.length >= 10 ? d : null;
}
