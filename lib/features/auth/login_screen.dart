// Hecho por Briann$ Workers Corp.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/env.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/plate_mark.dart';
import '../../data/gym_repository.dart';

/// Acceso del personal. Las cuentas se crean desde el panel de Supabase
/// (no hay registro público).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(supabaseClientProvider)!.auth.signInWithPassword(
            email: _email.text.trim(),
            password: _password.text,
          );
      refreshGymData(ref); // descarta lo cargado con una sesión anterior
    } on AuthException catch (e) {
      setState(() => _error = e.code == 'invalid_credentials' ? 'Correo o contraseña incorrectos' : e.message);
    } catch (_) {
      setState(() => _error = 'No se pudo conectar. Revisa la conexión a internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: PlateMark(size: 72)),
                  const SizedBox(height: 18),
                  Text(Env.gymName.toUpperCase(), textAlign: TextAlign.center, style: AppText.score(56)),
                  const SizedBox(height: 4),
                  Text('WORKERS RECEPCIÓN', textAlign: TextAlign.center, style: AppText.label),
                  const SizedBox(height: 18),
                  Container(height: 3, color: AppColors.ink),
                  const SizedBox(height: 2),
                  Container(height: 1, color: AppColors.ink),
                  const SizedBox(height: 28),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline)),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => (v ?? '').contains('@') ? null : 'Ingresa un correo válido',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Contraseña', prefixIcon: Icon(Icons.lock_outline)),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (v) => (v ?? '').isEmpty ? 'Ingresa la contraseña' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // Firma al pie de la pantalla.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16, top: 8),
          child: Text(
            'Hecho por Briann\$',
            textAlign: TextAlign.center,
            style: AppText.mono(size: 12, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}
