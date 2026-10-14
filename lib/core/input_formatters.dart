// Hecho por Briann$ Workers Corp.
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Filtros de escritura: lo que no es válido simplemente no entra al campo.

/// Montos: dígitos y un solo separador decimal (coma o punto), máximo 2 decimales.
/// "30", "30,5", "1250.75". Nada de letras ni símbolos.
class MoneyInputFormatter extends TextInputFormatter {
  const MoneyInputFormatter({this.decimals = 2});

  final int decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final pattern = RegExp(r'^\d{0,9}([.,]\d{0,' '$decimals' r'})?$');
    return pattern.hasMatch(text) ? newValue : oldValue;
  }
}

/// Solo dígitos con puntos de miles mientras se escribe: "24518330" → "24.518.330".
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({this.maxDigits = 9});

  final int maxDigits;
  static final _format = NumberFormat('#,###', 'es');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);
    if (digits.isEmpty) return const TextEditingValue();
    final text = _format.format(int.parse(digits));
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Teléfono venezolano: solo dígitos (máx. 11) mostrados como "0414-555-0192".
class PhoneInputFormatter extends TextInputFormatter {
  const PhoneInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var d = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (d.length > 11) d = d.substring(0, 11);
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 4 || i == 7) b.write('-');
      b.write(d[i]);
    }
    final text = b.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Cantidades enteras (stock, unidades, días).
final digitsOnly = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)];
