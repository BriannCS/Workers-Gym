// Hecho por Briann$ Workers Corp.
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/formatters.dart';
import '../../core/widgets/brand_mark.dart' show brandSignature;
import '../../domain/models.dart';

/// Un renglón del cierre: un pago de membresía o una venta de tienda.
class CashMovement {
  CashMovement.payment(Payment this.payment) : sale = null;
  CashMovement.sale(Sale this.sale) : payment = null;

  final Payment? payment;
  final Sale? sale;

  bool get isStore => sale != null;
  DateTime get at => payment?.paidAt ?? sale!.soldAt;
  String get detail =>
      payment != null ? '${payment!.memberName} · ${payment!.planName}' : [sale!.description, ?sale!.memberName].join(' · ');
  String get methodName => payment?.methodName ?? sale!.methodName;
  int get usdCents => payment?.amountCents ?? sale!.totalCents;
  int? get vesCents => payment?.amountVesCents ?? sale?.totalVesCents;
  bool get voided => payment?.voided ?? sale!.voided;
  String? get voidReason => payment?.voidReason ?? sale?.voidReason;
}

/// Montos de un método en su moneda: "Bs. 52.608,00 ($60,00)" o "$60,00".
String methodAmount(MethodTotal t) =>
    t.currency == Currency.ves ? '${formatVes(t.vesCents)} (${formatMoney(t.usdCents)})' : formatMoney(t.usdCents);

/// Texto del cierre para compartir por WhatsApp (negritas con *).
String cashSummaryText({required String gymName, required DateTime day, required CashSummary summary}) {
  final b = StringBuffer()
    ..writeln('*$gymName · Cierre de caja*')
    ..writeln(DateFormat("EEEE d 'de' MMMM 'de' y", 'es').format(day))
    ..writeln()
    ..writeln('Membresías: ${formatMoney(summary.membershipCents)}')
    ..writeln('Tienda: ${formatMoney(summary.storeCents)}')
    ..writeln('*Total: ${formatMoney(summary.totalCents)}*');
  if (summary.totalVesCents > 0) b.writeln('Recibido en bolívares: ${formatVes(summary.totalVesCents)}');
  if (summary.byMethod.isNotEmpty) {
    b
      ..writeln()
      ..writeln('*Por método*');
    for (final t in summary.byMethod.values) {
      b.writeln('• ${t.name}: ${methodAmount(t)}');
    }
  }
  if (summary.voidedCount > 0) {
    b
      ..writeln()
      ..writeln('Anulaciones: ${summary.voidedCount} por ${formatMoney(summary.voidedCents)} (no suman)');
  }
  return b.toString().trim();
}

/// PDF del cierre como ticket Z de 80 mm (impresoras de recibos), con las
/// mismas fuentes de la app para que acentos y ñ salgan bien.
Future<List<int>> buildCashPdf({
  required String gymName,
  required DateTime day,
  required DateTime printedAt,
  required CashSummary summary,
  required List<CashMovement> movements,
}) async {
  Future<pw.Font> font(String file) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$file'));
  final mono = await font('PlexMono-400.ttf');
  final monoBold = await font('PlexMono-600.ttf');
  final display = await font('BigShoulders-800.ttf');

  pw.Widget line(String label, String value, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.Expanded(child: pw.Text(label, style: pw.TextStyle(font: bold ? monoBold : mono, fontSize: 8))),
          pw.Text(value, style: pw.TextStyle(font: bold ? monoBold : mono, fontSize: 8)),
        ]),
      );
  pw.Widget dashes() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        child: pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: .6, height: 1),
      );

  final doc = pw.Document(title: 'Cierre de caja ${isoDate(day)}', author: gymName);
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.roll80.copyWith(marginLeft: 12, marginRight: 12, marginTop: 14, marginBottom: 14),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(gymName.toUpperCase(), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: display, fontSize: 18)),
        pw.Text('CIERRE DE CAJA · Z', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: monoBold, fontSize: 8, letterSpacing: 1)),
        pw.SizedBox(height: 2),
        pw.Text(
          '${formatDate(day).toUpperCase()} · IMPRESO ${formatTime(printedAt)}',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: mono, fontSize: 7),
        ),
        dashes(),
        line('Membresías', formatMoney(summary.membershipCents)),
        line('Tienda', formatMoney(summary.storeCents)),
        dashes(),
        pw.Row(children: [
          pw.Expanded(child: pw.Text('TOTAL', style: pw.TextStyle(font: monoBold, fontSize: 9))),
          pw.Text(formatMoney(summary.totalCents), style: pw.TextStyle(font: display, fontSize: 22)),
        ]),
        if (summary.totalVesCents > 0) line('Recibido en Bs.', formatVes(summary.totalVesCents), bold: true),
        pw.SizedBox(height: 6),
        pw.Text('POR MÉTODO', style: pw.TextStyle(font: monoBold, fontSize: 7, letterSpacing: 1)),
        for (final t in summary.byMethod.values) line(t.name, methodAmount(t)),
        dashes(),
        line('Anulaciones (${summary.voidedCount})', summary.voidedCount == 0 ? '—' : formatMoney(summary.voidedCents)),
        dashes(),
        pw.Text('MOVIMIENTOS', style: pw.TextStyle(font: monoBold, fontSize: 7, letterSpacing: 1)),
        pw.SizedBox(height: 3),
        for (final m in movements)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 2),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.Row(children: [
                pw.Text('${formatTime(m.at)} ${m.isStore ? 'T' : 'M'}  ', style: pw.TextStyle(font: monoBold, fontSize: 7)),
                pw.Expanded(child: pw.Text(m.detail, style: pw.TextStyle(font: mono, fontSize: 7), maxLines: 2)),
              ]),
              pw.Row(children: [
                pw.Expanded(
                  child: pw.Text(
                    m.voided ? 'ANULADO: ${m.voidReason}' : m.methodName,
                    style: pw.TextStyle(font: mono, fontSize: 6.5, color: m.voided ? PdfColors.red700 : PdfColors.grey700),
                  ),
                ),
                pw.Text(
                  m.vesCents == null ? formatMoney(m.usdCents) : '${formatVes(m.vesCents!)} / ${formatMoney(m.usdCents)}',
                  style: pw.TextStyle(
                    font: mono,
                    fontSize: 7,
                    decoration: m.voided ? pw.TextDecoration.lineThrough : null,
                  ),
                ),
              ]),
            ]),
          ),
        dashes(),
        pw.Text('T = tienda · M = membresía', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 6)),
        pw.SizedBox(height: 4),
        pw.Text(brandSignature, textAlign: pw.TextAlign.center, style: pw.TextStyle(font: mono, fontSize: 6)),
      ],
    ),
  ));
  return doc.save();
}
