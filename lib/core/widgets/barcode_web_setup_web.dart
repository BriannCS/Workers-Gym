// Hecho por Briann$ - Workers Corp.
// En la web, el escáner usa el lector nativo del navegador (BarcodeDetector:
// Chrome en Android, Safari, Mac) y, si no existe (Chrome/Edge en Windows,
// Firefox), ZXing servido desde la propia app (web/zxing/), sin depender de un
// CDN externo.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:mobile_scanner/mobile_scanner.dart';

bool _prepared = false;

void prepareWebBarcodeReader() {
  if (_prepared) return;
  _prepared = true;
  if (globalContext.has('BarcodeDetector')) return;
  final platform = MobileScannerPlatform.instance as dynamic;
  // ignore: avoid_dynamic_calls
  platform.setWebBarcodeReader(WebBarcodeReader.zxingJs);
  platform.setBarcodeLibraryScriptUrl('zxing/zxing.min.js');
}
