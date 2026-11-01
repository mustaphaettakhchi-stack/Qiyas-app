import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../session/api_client.dart';
import '../../../session/auth_service.dart';
import '../../../session/session_controller.dart';
import '../../widgets/brand.dart' show PasswordField;
import '../../widgets/common.dart';

/// Création du mot de passe à partir d'un lien reçu : invitation ou nouveau mot de passe.
class InvitationScreen extends StatefulWidget {
  const InvitationScreen({super.key});

  @override
  State<InvitationScreen> createState() => _InvitationScreenState();
}

class _InvitationScreenState extends State<InvitationScreen> {
  final _link = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final token = invitationTokenFrom(_link.text);
    String? error;
    if (token == null) {
      error = 'Lien non reconnu. Copiez le lien complet reçu.';
    } else if (_password.text.length < 12) {
      error = 'Le mot de passe doit contenir au moins 12 caractères.';
    } else if (_password.text != _confirm.text) {
      error = 'Les deux mots de passe sont différents.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final auth = context.read<SessionController>().auth;
      final reset = isPasswordResetLink(_link.text);
      if (reset) {
        await auth.acceptPasswordReset(token!, _password.text);
      } else {
        await auth.acceptInvitation(token!, _password.text);
      }
      messenger.showSnackBar(SnackBar(
        content: Text(reset
            ? 'Mot de passe modifié. Connectez-vous avec ce nouveau mot de passe.'
            : 'Compte créé. Connectez-vous avec votre adresse e-mail et ce mot de passe.'),
      ));
      nav.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('J\'ai reçu un lien')),
        body: AutofillGroup(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Text(
              'Collez le lien reçu (invitation ou nouveau mot de passe), puis choisissez votre mot de passe.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _link,
              autocorrect: false,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Lien reçu'),
            ),
            const SizedBox(height: 12),
            PasswordField(controller: _password, label: 'Nouveau mot de passe', newPassword: true),
            const SizedBox(height: 12),
            PasswordField(controller: _confirm, label: 'Confirmez le mot de passe', newPassword: true),
            const SizedBox(height: 8),
            Text(
              'Au moins 12 caractères. Le plus sûr : une phrase de quatre mots ou plus sans lien entre eux, '
              'que vous n\'utilisez nulle part ailleurs.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _submit, child: const Text('Valider le mot de passe')),
            if (_error != null) ...[const SizedBox(height: 12), AlertBox(_error!, kind: AlertKind.error)],
          ]),
        ),
      );
}
