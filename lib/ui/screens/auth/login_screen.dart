import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/config.dart';
import '../../../session/api_client.dart';
import '../../../session/auth_service.dart';
import '../../../session/session_controller.dart';
import '../../widgets/brand.dart';
import '../../widgets/common.dart';
import 'invitation_screen.dart';
import 'mfa_screens.dart';

/// Connexion : e-mail et mot de passe, puis double authentification.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final TextEditingController _server;
  bool _busy = false;
  String? _error;
  bool _showServer = false;

  @override
  void initState() {
    super.initState();
    final current = context.read<SessionController>().api.baseUrl ?? '';
    _server = TextEditingController(text: current);
    _showServer = current.isEmpty;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<bool> _applyServer() async {
    final api = context.read<SessionController>().api;
    final url = normalizeApiUrl(_server.text);
    if (url == null) {
      setState(() {
        _showServer = true;
        _error = 'Adresse du serveur invalide. Elle doit commencer par https://';
      });
      return false;
    }
    if (url != api.baseUrl) await api.setBaseUrl(url);
    return true;
  }

  Future<void> _login() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email) || _password.text.isEmpty) {
      setState(() => _error = 'Saisissez votre adresse e-mail et votre mot de passe.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    try {
      if (!await _applyServer()) return;
      final step = await session.auth.login(email, _password.text);
      _password.clear();
      switch (step) {
        case LoginDone():
          await session.completeLogin();
        case LoginNeedsCode(:final mfaToken):
          await nav.push(MaterialPageRoute<void>(builder: (_) => MfaVerifyScreen(mfaToken: mfaToken)));
        case LoginNeedsMfaSetup(:final mfaToken):
          await nav.push(MaterialPageRoute<void>(builder: (_) => MfaSetupScreen(mfaToken: mfaToken)));
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final session = context.read<SessionController>();
    return Scaffold(
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const SizedBox(height: 16),
            const Center(child: LogoTile()),
            const SizedBox(height: 16),
            Text('Du relevé au devis, sur le chantier.', textAlign: TextAlign.center, style: t.titleMedium),
            const SizedBox(height: 28),
            if (AppConfig.demoMode) ...[
              const AlertBox(
                'Version de démonstration : aucune donnée n\'est envoyée à un serveur.',
                kind: AlertKind.warning,
              ),
              const SizedBox(height: 8),
              OutlinedButton(onPressed: session.enterDemo, child: const Text('Continuer sans serveur')),
              const Divider(height: 32),
            ],
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(labelText: 'Adresse e-mail'),
            ),
            const SizedBox(height: 12),
            PasswordField(controller: _password, onSubmitted: (_) => _busy ? null : _login()),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Se connecter'),
            ),
            if (_error != null) ...[const SizedBox(height: 12), AlertBox(_error!, kind: AlertKind.error)],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                if (!await _applyServer() || !context.mounted) return;
                await Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const InvitationScreen()));
              },
              child: const Text('J\'ai reçu un lien (invitation, mot de passe)'),
            ),
            TextButton(
              onPressed: () => setState(() => _showServer = !_showServer),
              child: Text(_showServer ? 'Masquer l\'adresse du serveur' : 'Adresse du serveur'),
            ),
            if (_showServer)
              TextField(
                controller: _server,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Adresse du serveur LAMAALAM',
                  hintText: 'https://…',
                  helperText: 'Fournie par votre administrateur.',
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
