// Hecho por Briann$ - Workers Corp.
// Comprobante de pago (pago móvil, transferencia, Zelle…): referencia, banco,
// quién pagó y la foto. Se usa al cobrar membresías y al vender en la tienda,
// y después para ver, cambiar la foto o verificar el pago contra el banco.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';

/// Lo que se va llenando en el formulario de cobro.
class ProofDraft extends ChangeNotifier {
  final reference = TextEditingController();
  final bank = TextEditingController();
  final payerId = TextEditingController();
  Uint8List? photo;
  String photoType = 'image/jpeg';

  ProofDraft() {
    for (final c in [reference, bank, payerId]) {
      c.addListener(notifyListeners);
    }
  }

  ProofInput get input => ProofInput(reference: reference.text, payerBank: bank.text, payerId: payerId.text);

  void setPhoto(Uint8List? bytes, [String type = 'image/jpeg']) {
    photo = bytes;
    photoType = type;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in [reference, bank, payerId]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// Foto del comprobante: cámara trasera o galería, reducida para que suba
/// rápido pero se lea la referencia (1600 px).
Future<(Uint8List, String)?> pickReceiptPhoto(BuildContext context, ImageSource source) async {
  try {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
    if (file == null) return null;
    return (await file.readAsBytes(), file.mimeType ?? 'image/jpeg');
  } catch (e) {
    if (context.mounted) showToast(context, 'No se pudo abrir la cámara o la galería: $e', error: true);
    return null;
  }
}

/// Campos del comprobante. Solo se muestran si el método pide referencia.
class ProofFields extends StatelessWidget {
  const ProofFields({super.key, required this.draft, required this.method});

  final ProofDraft draft;
  final PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    if (!method.requiresReference) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: draft,
      builder: (context, _) {
        final problem = draft.input.problemFor(method);
        final bank = LayoutBuilder(
          builder: (context, c) => DropdownMenu<String>(
            controller: draft.bank,
            width: c.maxWidth,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 280,
            label: Text(method.inBolivares ? 'Banco de origen' : 'Banco o plataforma'),
            dropdownMenuEntries: [
              if (method.inBolivares)
                for (final b in venezuelanBanks) DropdownMenuEntry(value: b, label: b),
            ],
          ),
        );
        return Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderStrong),
            borderRadius: BorderRadius.circular(AppTheme.radius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 12,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('COMPROBANTE · ${method.name.toUpperCase()}', style: AppText.label.copyWith(color: AppColors.ink)),
                  ),
                ],
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final ref = TextField(
                    controller: draft.reference,
                    decoration: InputDecoration(
                      labelText: 'Referencia *',
                      hintText: 'Últimos dígitos o número completo',
                      errorText: draft.reference.text.isEmpty ? null : problem,
                    ),
                    textCapitalization: TextCapitalization.characters,
                  );
                  final id = TextField(
                    controller: draft.payerId,
                    decoration: const InputDecoration(labelText: 'Cédula o teléfono de quien pagó'),
                  );
                  if (c.maxWidth < 480) return Column(spacing: 12, children: [ref, bank, id]);
                  return Column(
                    spacing: 12,
                    children: [
                      Row(
                        spacing: 12,
                        children: [
                          Expanded(child: ref),
                          Expanded(child: id),
                        ],
                      ),
                      bank,
                    ],
                  );
                },
              ),
              _PhotoRow(draft: draft),
            ],
          ),
        );
      },
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({required this.draft});

  final ProofDraft draft;

  @override
  Widget build(BuildContext context) {
    final photo = draft.photo;
    final compact = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
    );
    Future<void> pick(ImageSource s) async {
      final picked = await pickReceiptPhoto(context, s);
      if (picked != null) draft.setPhoto(picked.$1, picked.$2);
    }

    return Row(
      children: [
        GestureDetector(
          onTap: photo == null ? null : () => _showFullImage(context, MemoryImage(photo)),
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.raised,
              border: Border.all(color: AppColors.borderStrong),
              borderRadius: BorderRadius.circular(AppTheme.radius),
              image: photo == null ? null : DecorationImage(image: MemoryImage(photo), fit: BoxFit.cover),
            ),
            child: photo == null ? const Icon(Icons.image_outlined, color: AppColors.textMuted) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                style: compact,
                onPressed: () => pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(photo == null ? 'Foto del comprobante' : 'Otra foto'),
              ),
              OutlinedButton.icon(
                style: compact,
                onPressed: () => pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Galería'),
              ),
              if (photo != null)
                IconButton(tooltip: 'Quitar foto', onPressed: () => draft.setPhoto(null), icon: const Icon(Icons.close, size: 18)),
              if (photo == null) Text('Opcional', style: AppText.muted.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Después de registrar el cobro: sube la foto si hay. Si falla, el cobro ya
/// quedó; se avisa para adjuntarla luego desde el detalle.
Future<void> uploadDraftReceipt(BuildContext context, WidgetRef ref, ProofDraft draft, ProofKind kind, String id) async {
  final photo = draft.photo;
  if (photo == null) return;
  try {
    await ref.read(gymRepositoryProvider).attachReceipt(kind, id, photo, mimeType: draft.photoType);
  } catch (e) {
    if (context.mounted) {
      showToast(
        context,
        'El cobro quedó registrado, pero la foto no se subió: ${friendlyError(e)}. Adjúntala desde el detalle.',
        error: true,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Insignia y detalle

/// "POR VERIFICAR" / "VERIFICADO" junto al pago, más un clip si tiene foto.
class ProofBadge extends StatelessWidget {
  const ProofBadge({super.key, required this.proof});

  final PaymentProof? proof;

  @override
  Widget build(BuildContext context) {
    final p = proof;
    if (p == null || (p.reference == null && !p.hasReceipt)) return const SizedBox.shrink();
    final color = p.verified ? AppColors.success : AppColors.warning;
    // Se encoge si la columna es angosta (tabla de pagos en tableta).
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Tooltip(
            message: p.verified ? 'Confirmado contra el banco' : 'Falta confirmarlo contra el banco',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: color, width: 1.2),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(p.verified ? Icons.verified_outlined : Icons.hourglass_empty, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(p.verified ? 'VERIFICADO' : 'POR VERIFICAR', style: AppText.label.copyWith(fontSize: 9.5, color: color)),
                ],
              ),
            ),
          ),
          if (p.hasReceipt)
            const Tooltip(
              message: 'Tiene foto del comprobante',
              child: Icon(Icons.attach_file, size: 15, color: AppColors.textMuted),
            ),
        ],
      ),
    );
  }
}

void _showFullImage(BuildContext context, ImageProvider image) => showDialog<void>(
  context: context,
  builder: (context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: Stack(
      children: [
        InteractiveViewer(
          maxScale: 5,
          child: Image(image: image, fit: BoxFit.contain),
        ),
        Positioned(
          right: 4,
          top: 4,
          child: IconButton.filled(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ),
      ],
    ),
  ),
);

/// Detalle del comprobante de un cobro o venta: datos, foto (tocar para
/// ampliar), cambiar la foto y verificar contra el banco.
Future<void> showProofDetail(
  BuildContext context, {
  required ProofKind kind,
  required String id,
  required PaymentProof? proof,
  required String title,
  required String amountLabel,
  required String methodName,
  String? createdBy,
  bool voided = false,
}) => showDialog(
  context: context,
  builder: (_) => _ProofDetail(
    kind: kind,
    id: id,
    proof: proof,
    title: title,
    amountLabel: amountLabel,
    methodName: methodName,
    createdBy: createdBy,
    voided: voided,
  ),
);

class _ProofDetail extends ConsumerStatefulWidget {
  const _ProofDetail({
    required this.kind,
    required this.id,
    required this.proof,
    required this.title,
    required this.amountLabel,
    required this.methodName,
    required this.createdBy,
    required this.voided,
  });

  final ProofKind kind;
  final String id;
  final PaymentProof? proof;
  final String title;
  final String amountLabel;
  final String methodName;
  final String? createdBy;
  final bool voided;

  @override
  ConsumerState<_ProofDetail> createState() => _ProofDetailState();
}

class _ProofDetailState extends ConsumerState<_ProofDetail> {
  late PaymentProof _proof = widget.proof ?? const PaymentProof();
  bool _busy = false;

  void _refresh() => ref
    ..invalidate(paymentsProvider)
    ..invalidate(memberPaymentsProvider)
    ..invalidate(salesProvider)
    ..invalidate(cashDayProvider);

  Future<void> _changePhoto(ImageSource source) async {
    final picked = await pickReceiptPhoto(context, source);
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final path = await ref.read(gymRepositoryProvider).attachReceipt(widget.kind, widget.id, picked.$1, mimeType: picked.$2);
      _refresh();
      if (mounted) setState(() => _proof = _proof.copyWith(receiptPath: () => path));
      if (mounted) showToast(context, 'Foto del comprobante guardada');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo subir la foto: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setVerified(bool v) async {
    setState(() => _busy = true);
    try {
      await ref.read(gymRepositoryProvider).setPaymentVerified(widget.kind, widget.id, v);
      _refresh();
      if (mounted) setState(() => _proof = _proof.copyWith(verifiedAt: () => v ? ref.read(clockProvider)() : null));
      if (mounted) showToast(context, v ? 'Pago verificado' : 'Verificación quitada');
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo cambiar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentStaffProvider).value;
    final canVerify = !widget.voided && (me?.can(Perm.paymentsVerify) ?? false);
    final canAttach =
        !widget.voided &&
        (me?.can(widget.kind == ProofKind.payment ? Perm.paymentsCreate : Perm.storeSell) ?? false) &&
        (!_proof.hasReceipt || widget.createdBy == me?.userId || canVerify);
    final path = _proof.receiptPath;
    final compact = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      visualDensity: VisualDensity.compact,
    );

    return FormDialog(
      title: 'Comprobante',
      subtitle: '${widget.title} · ${widget.amountLabel}',
      width: 560,
      actions: [
        if (canVerify && _proof.reference != null)
          _proof.verified
              ? OutlinedButton(onPressed: _busy ? null : () => _setVerified(false), child: const Text('Quitar verificación'))
              : FilledButton.icon(
                  onPressed: _busy ? null : () => _setVerified(true),
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Verificar pago'),
                ),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 4,
        children: [
          if (widget.voided)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'Pago anulado: el comprobante se conserva.',
                style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600),
              ),
            ),
          LeaderLine('Método', widget.methodName),
          LeaderLine('Referencia', _proof.reference ?? '—', strong: true),
          LeaderLine('Banco', _proof.payerBank ?? '—'),
          LeaderLine('Pagó', _proof.payerId ?? '—'),
          LeaderLine(
            'Estado',
            _proof.reference == null
                ? 'Sin referencia'
                : (_proof.verified ? 'Verificado · ${formatDate(_proof.verifiedAt!)}' : 'Por verificar'),
            color: _proof.verified ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(height: 14),
          Text('FOTO DEL COMPROBANTE', style: AppText.label),
          const SizedBox(height: 8),
          if (path == null)
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(AppTheme.radius)),
              child: Text('Sin foto', style: AppText.muted),
            )
          else
            Consumer(
              builder: (context, ref, _) => switch (ref.watch(receiptImageProvider(path))) {
                AsyncData(:final value) => GestureDetector(
                  onTap: () => _showFullImage(context, value),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: Image(image: value, fit: BoxFit.contain),
                    ),
                  ),
                ),
                AsyncError(:final error) => Text(
                  'No se pudo cargar la foto: ${friendlyError(error)}',
                  style: const TextStyle(color: AppColors.danger),
                ),
                _ => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
              },
            ),
          if (canAttach) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  style: compact,
                  onPressed: _busy ? null : () => _changePhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: Text(path == null ? 'Tomar foto' : 'Cambiar foto'),
                ),
                OutlinedButton.icon(
                  style: compact,
                  onPressed: _busy ? null : () => _changePhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Galería'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
