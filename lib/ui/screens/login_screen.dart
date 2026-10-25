import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/app_state.dart';
import '../../services/auth_service.dart';
import '../widgets/common.dart';

/// E1 · Inscription et connexion par SMS.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _normalized;
  int _triesLeft = 3;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final n = normalizeMoroccanPhone(_phone.text);
    if (n == null) {
      setState(() => _error = 'Numéro marocain attendu : 9 chiffres commençant par 5, 6 ou 7.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await context.read<AuthService>().requestCode(n);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _normalized = n;
      _triesLeft = 3;
    });
  }

  Future<void> _verify() async {
    if (_triesLeft <= 0) return;
    setState(() => _busy = true);
    final ok = await context.read<AuthService>().verifyCode(_normalized!, _code.text);
    if (!mounted) return;
    if (ok) {
      context.read<AppState>().signIn(_normalized!);
      return;
    }
    setState(() {
      _busy = false;
      _triesLeft--;
      _error = _triesLeft > 0
          ? 'Code incorrect. Il vous reste $_triesLeft essai${_triesLeft > 1 ? 's' : ''}.'
          : 'Trop d\'essais. Demandez un nouveau code.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthService>();
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 40),
          Text('Qiyas', style: t.displayMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('Du relevé au devis, sur le chantier.', style: t.titleMedium),
          const SizedBox(height: 32),
          if (_normalized == null) ...[
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: const InputDecoration(labelText: 'Votre numéro de téléphone', prefixText: '+212 '),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _send, child: const Text('Recevoir le code par SMS')),
            const SizedBox(height: 12),
            Text(
              'En continuant, vous acceptez les conditions d\'utilisation et le traitement de vos données, '
              'déclaré à la CNDP (loi 09-08).',
              style: t.bodySmall,
            ),
          ] else ...[
            AlertBox('Code envoyé au +212 $_normalized.${auth.demoHint == null ? '' : ' ${auth.demoHint}'}'),
            const SizedBox(height: 16),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofillHints: const [AutofillHints.oneTimeCode],
              textAlign: TextAlign.center,
              style: t.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: const InputDecoration(labelText: 'Code à 6 chiffres', counterText: ''),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy || _triesLeft <= 0 ? null : _verify, child: const Text('Valider')),
            TextButton(onPressed: () => setState(() => _normalized = null), child: const Text('Changer de numéro')),
          ],
          if (_error != null) ...[const SizedBox(height: 12), AlertBox(_error!, kind: AlertKind.error)],
        ]),
      ),
    );
  }
}
