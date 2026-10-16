// Hecho por Briann$ Workers Corp.
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/formatters.dart';
import '../../core/input_formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/gym_repository.dart';
import '../../domain/models.dart';
import '../../domain/staff.dart';
import '../attendance/check_in.dart';
import '../payments/payment_dialog.dart';
import 'member_actions.dart';

Future<void> showMemberForm(BuildContext context, {Member? member}) =>
    showDialog(context: context, builder: (_) => _MemberForm(member: member));

Future<void> showMemberDetail(BuildContext context, Member member) =>
    showDialog(context: context, builder: (_) => _MemberDetail(memberId: member.id));

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm({this.member});

  final Member? member;

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.member?.fullName);
  // Cédula: nacionalidad aparte y solo números ("24.518.330").
  late String _nationality = (widget.member?.documentId ?? '').startsWith('E') ? 'E' : 'V';
  late final _doc = TextEditingController(
    text: onlyDigits(widget.member?.documentId).isEmpty ? '' : formatDocument(onlyDigits(widget.member?.documentId)),
  );
  late final _phone = TextEditingController(text: onlyDigits(widget.member?.phone).isEmpty ? '' : formatPhone(widget.member?.phone));
  late final _email = TextEditingController(text: widget.member?.email);
  late final _notes = TextEditingController(text: widget.member?.notes);
  Uint8List? _newPhoto;
  String _newPhotoType = 'image/jpeg';
  bool _removePhoto = false;
  late bool _active = widget.member?.active ?? true;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _doc, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  static final _compact = OutlinedButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    visualDensity: VisualDensity.compact,
  );

  /// Cámara (en el teléfono abre la cámara directamente) o galería. Se reduce
  /// a 600 px para que suba rápido y no ocupe espacio de más.
  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 600,
        maxHeight: 600,
        imageQuality: 82,
        preferredCameraDevice: CameraDevice.front,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _newPhoto = bytes;
        _newPhotoType = file.mimeType ?? 'image/jpeg';
        _removePhoto = false;
      });
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo abrir la cámara o la galería: $e', error: true);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final docDigits = onlyDigits(_doc.text);
    final input = MemberInput(
      fullName: _name.text.trim(),
      documentId: docDigits.isEmpty ? null : '$_nationality-$docDigits',
      phone: onlyDigits(_phone.text).isEmpty ? null : onlyDigits(_phone.text),
      email: _opt(_email),
      notes: _opt(_notes),
    );
    final repo = ref.read(gymRepositoryProvider);
    try {
      final existing = widget.member;
      final Member saved;
      if (existing == null) {
        saved = await repo.createMember(input);
      } else {
        await repo.updateMember(existing.id, input);
        if (_active != existing.active) await repo.setMemberActive(existing.id, _active);
        saved = existing;
      }
      if (_newPhoto != null) {
        await repo.setMemberPhoto(saved, _newPhoto!, mimeType: _newPhotoType);
      } else if (_removePhoto) {
        await repo.removeMemberPhoto(saved);
      }
      refreshGymData(ref);
      if (!mounted) return;
      Navigator.pop(context);
      showToast(context, existing == null ? '${input.fullName} registrado' : 'Datos actualizados');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      showToast(context, e.code == '23505' ? 'Ya existe un cliente con esa cédula' : e.message, error: true);
    } catch (e) {
      if (mounted) showToast(context, 'No se pudo guardar: ${friendlyError(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.member != null;
    final photos = ref.watch(memberPhotosProvider).value ?? const <String, ImageProvider>{};
    final current = editing && !_removePhoto ? photos[widget.member!.id] : null;
    final ImageProvider? photo = _newPhoto != null ? MemoryImage(_newPhoto!) : current;
    final docField = TextFormField(
      controller: _doc,
      decoration: InputDecoration(
        labelText: 'Cédula',
        hintText: '24.518.330',
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _nationality,
              items: [for (final n in const ['V', 'E']) DropdownMenuItem(value: n, child: Text('$n-', style: AppText.mono(size: 14)))],
              onChanged: (v) => setState(() => _nationality = v!),
            ),
          ),
        ),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: const [ThousandsInputFormatter(maxDigits: 9)],
      validator: (v) {
        final d = onlyDigits(v);
        return d.isEmpty || (d.length >= 6 && d.length <= 9) ? null : 'Cédula de 6 a 9 dígitos';
      },
    );
    final phoneField = TextFormField(
      controller: _phone,
      decoration: const InputDecoration(labelText: 'Teléfono', hintText: '0414-555-0192'),
      keyboardType: TextInputType.phone,
      inputFormatters: const [PhoneInputFormatter()],
      validator: (v) {
        final d = onlyDigits(v);
        return d.isEmpty || d.length >= 10 ? null : 'Teléfono incompleto';
      },
    );
    return FormDialog(
      title: editing ? 'Editar cliente' : 'Nuevo cliente',
      subtitle: editing ? widget.member!.fullName : 'Datos básicos para identificarlo en recepción',
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy ? null : _save, child: Text(editing ? 'Guardar cambios' : 'Registrar cliente')),
      ],
      child: Form(
        key: _form,
        child: Column(
          spacing: 14,
          children: [
            // Foto de perfil
            Row(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: AppColors.raised,
                    border: Border.all(color: AppColors.ink, width: 1.5),
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    image: photo == null ? null : DecorationImage(image: photo, fit: BoxFit.cover),
                  ),
                  child: photo == null ? const Icon(Icons.person_outline, size: 36, color: AppColors.textMuted) : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: _compact,
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Cámara'),
                      ),
                      OutlinedButton.icon(
                        style: _compact,
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text('Galería'),
                      ),
                      if (photo != null)
                        TextButton(
                          onPressed: () => setState(() {
                            _newPhoto = null;
                            _removePhoto = true;
                          }),
                          child: const Text('Quitar'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _name,
              autofocus: !context.isPhone,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre completo *'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'Ingresa el nombre y apellido' : null,
            ),
            if (context.isPhone) ...[docField, phoneField]
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [Expanded(child: docField), Expanded(child: phoneField)],
              ),
            TextFormField(
              controller: _email,
              decoration: const InputDecoration(labelText: 'Correo'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => (v ?? '').trim().isEmpty || v!.contains('@') ? null : 'Correo inválido',
            ),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notas', hintText: 'Lesiones, objetivos, observaciones…'),
              maxLines: 3,
            ),
            if (editing && ref.watch(canProvider(Perm.membersDelete)))
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                contentPadding: EdgeInsets.zero,
                title: const Text('Cliente activo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  _active ? 'Aparece en avisos de vencimiento' : 'Inactivo: no cuenta en vencidos ni por vencer',
                  style: AppText.muted.copyWith(fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MemberDetail extends ConsumerWidget {
  const _MemberDetail({required this.memberId});

  final String memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Se busca por id para reflejar cambios (pagos, ediciones) sin cerrar el diálogo.
    final members = ref.watch(membersProvider).value;
    final member = members?.where((m) => m.id == memberId).firstOrNull;
    if (member == null) {
      // Lo eliminaron (aquí o en otro dispositivo): se cierra la ficha.
      if (members != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.maybePop(context);
        });
      }
      return const SizedBox.shrink();
    }
    final today = ref.watch(clockProvider)();
    final status = member.status(today);
    final payments = ref.watch(memberPaymentsProvider(member.id));
    final phone = context.isPhone;

    return FormDialog(
      title: member.fullName,
      subtitle: 'Cliente desde ${formatDate(member.createdAt)}',
      width: 640,
      headerActions: [
        if (ref.watch(canProvider(Perm.membersEdit)))
          IconButton(
            tooltip: 'Editar',
            onPressed: () => showMemberForm(context, member: member),
            icon: const Icon(Icons.edit_outlined),
          ),
        if (ref.watch(canProvider(Perm.membersEdit)) || ref.watch(canProvider(Perm.membersDelete)))
          IconButton(
            tooltip: 'Más opciones',
            onPressed: () => showMemberActions(context, member),
            icon: const Icon(Icons.more_vert),
          ),
      ],
      actions: [
        if (ref.watch(canProvider(Perm.attendanceCreate)))
          OutlinedButton.icon(
            onPressed: () => checkInMember(context, ref, member),
            icon: const Icon(Icons.login, size: 18),
            label: Text(phone ? 'Entrada' : 'Registrar entrada'),
          ),
        if (ref.watch(canProvider(Perm.paymentsCreate)))
          FilledButton.icon(
            onPressed: () => showPaymentDialog(context, member: member),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(phone ? 'Cobrar' : 'Registrar pago'),
          )
        else
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MembershipBanner(member: member, status: status, today: today),
          const SizedBox(height: 20),
          Wrap(
            spacing: 32,
            runSpacing: 16,
            children: [
              _Field('Cédula', member.documentId == null ? null : formatDocument(member.documentId)),
              _Field('Teléfono', member.phone == null ? null : formatPhone(member.phone)),
              _Field('Correo', member.email),
            ],
          ),
          if (member.notes != null) ...[
            const SizedBox(height: 16),
            _Field('Notas', member.notes),
          ],
          const SizedBox(height: 24),
          const Text('Historial de pagos', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          AsyncView(
            payments,
            data: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Sin pagos registrados')
                : Container(
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      children: [
                        for (final (i, p) in list.indexed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: i == 0 ? null : const Border(top: BorderSide(color: AppColors.border)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p.planName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                      Text('${formatShortDate(p.periodStart)} – ${formatDate(p.periodEnd)}',
                                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    p.voided ? 'Anulado: ${p.voidReason}' : '${p.methodName} · ${formatShortDate(p.paidAt)}',
                                    style: TextStyle(color: p.voided ? AppColors.danger : AppColors.textMuted, fontSize: 13),
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      formatMoney(p.amountCents),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        decoration: p.voided ? TextDecoration.lineThrough : null,
                                        color: p.voided ? AppColors.textMuted : null,
                                      ),
                                    ),
                                    if (p.amountVesCents != null)
                                      Text(formatVes(p.amountVesCents!), style: AppText.mono(size: 11, color: AppColors.plateBlue)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _MembershipBanner extends StatelessWidget {
  const _MembershipBanner({required this.member, required this.status, required this.today});

  final Member member;
  final MembershipStatus status;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forStatus(status);
    final expires = member.expiresOn;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Initials(member, size: 72, status: status),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(status),
                const SizedBox(height: 6),
                Text(
                  expires == null
                      ? 'Todavía no tiene ningún pago registrado'
                      : '${member.planName ?? 'Plan'} · hasta el ${formatDate(expires)} (${relativeDays(daysLeft(expires, today))})',
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        const SizedBox(height: 2),
        Text(value ?? '—', style: const TextStyle(fontSize: 14)),
      ],
    );
  }
}
