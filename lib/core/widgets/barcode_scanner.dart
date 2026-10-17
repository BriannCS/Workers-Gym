// Hecho por Briann$ - Workers Corp.
// Escanear códigos de barras o QR con la cámara (Android, iPhone, Mac y la
// web). En la PC con Windows el lector USB escribe el código como un teclado,
// así que no hace falta botón.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme/app_theme.dart';
import 'barcode_web_setup_stub.dart' if (dart.library.js_interop) 'barcode_web_setup_web.dart';
import 'ui.dart';

/// ¿Hay cámara utilizable para escanear en esta plataforma?
bool get canScanBarcodes =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

/// Botón de cámara para poner junto a un campo de código.
class ScanButton extends StatelessWidget {
  const ScanButton({super.key, required this.onScanned, this.tooltip = 'Escanear código'});

  final ValueChanged<String> onScanned;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    if (!canScanBarcodes) return const SizedBox.shrink();
    return IconButton(
      tooltip: tooltip,
      icon: const Icon(Icons.qr_code_scanner),
      onPressed: () async {
        final code = await scanBarcode(context);
        if (code != null) onScanned(code);
      },
    );
  }
}

/// Abre la cámara y devuelve el primer código que lea (null si se cancela).
Future<String?> scanBarcode(BuildContext context) {
  prepareWebBarcodeReader();
  return Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScannerPage()));
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf14,
      BarcodeFormat.codabar,
      BarcodeFormat.qrCode,
      BarcodeFormat.dataMatrix,
    ],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final code = capture.barcodes.map((b) => b.rawValue?.trim()).whereType<String>().where((c) => c.isNotEmpty).firstOrNull;
    if (code == null) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear código'),
        actions: [
          IconButton(tooltip: 'Linterna', onPressed: _controller.toggleTorch, icon: const Icon(Icons.flashlight_on_outlined)),
          IconButton(tooltip: 'Cambiar cámara', onPressed: _controller.switchCamera, icon: const Icon(Icons.cameraswitch_outlined)),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ScannerError(error: error),
          ),
          // Marco guía (se oculta si la cámara no abrió).
          ValueListenableBuilder(
            valueListenable: _controller,
            builder: (context, state, _) => state.error != null ? const SizedBox.shrink() : const _Guide(),
          ),
        ],
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Center(
            child: Container(
              width: 280,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.plateYellow, width: 3),
                borderRadius: BorderRadius.circular(AppTheme.radius * 2),
              ),
            ),
          ),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 40,
          child: Text(
            'Apunta al código de barras o QR del empaque',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ScannerError extends StatelessWidget {
  const _ScannerError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final message = switch (error.errorCode) {
      MobileScannerErrorCode.permissionDenied =>
        'No hay permiso para usar la cámara. Actívalo en los ajustes del teléfono o del navegador.',
      MobileScannerErrorCode.unsupported => 'Este dispositivo o navegador no puede escanear. Escribe el código a mano.',
      _ => 'No se pudo abrir la cámara (${error.errorDetails?.message ?? error.errorCode.name}). Escribe el código a mano.',
    };
    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: EmptyState(icon: Icons.no_photography_outlined, title: 'Sin cámara', message: message),
          ),
        ),
      ),
    );
  }
}
