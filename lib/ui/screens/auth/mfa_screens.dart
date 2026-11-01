import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../session/api_client.dart';
import '../../../session/auth_service.dart';
import '../../../session/session_controller.dart';
import '../../widgets/common.dart';

/// Champ de saisie d'un code à 6 chiffres.
class _CodeField extends StatelessWidget {
  const _CodeField({required this.controller, this.onSubmitted});
  final TextEditingController controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        maxLength: 6,
        autofillHints: const [AutofillHints.oneTimeCode],
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 8),
        decoration: const InputDecoration(labelText: 'Code à 6 chiffres', counterText: ''),
        onSubmitted: onSubmitted,
      );
}

/// Deuxième étape de connexion : code de l'application d'authentification ou code de secours.
class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key, required this.mfaToken});
  final String mfaToken;

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  final _code = TextEditingController();
  bool _backup = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _code.text.trim();
    if (value.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    try {
      await session.auth.mfaVerify(widget.mfaToken, code: _backup ? null : value, backupCode: _backup ? value : null);
      await session.completeLogin();
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Vérification')),
        body: ListView(padding: const EdgeInsets.all(24), children: [
          Text(
            _backup
                ? 'Saisissez un de vos codes de secours (format XXXXX-XXXXX). Chaque code ne sert qu\'une fois.'
                : 'Ouvrez votre application d\'authentification et saisissez le code LAMAALAM.',
          ),
          const SizedBox(height: 16),
          if (_backup)
            TextField(
              controller: _code,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Code de secours'),
              onSubmitted: (_) => _submit(),
            )
          else
            _CodeField(controller: _code, onSubmitted: (_) => _submit()),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Valider')),
          if (_error != null) ...[const SizedBox(height: 12), AlertBox(_error!, kind: AlertKind.error)],
          TextButton(
            onPressed: () => setState(() {
              _backup = !_backup;
              _code.clear();
              _error = null;
            }),
            child: Text(_backup ? 'Utiliser le code de l\'application' : 'J\'ai perdu mon téléphone : code de secours'),
          ),
        ]),
      );
}

/// Mise en place obligatoire de la double authentification (administrateurs et collaborateurs).
class MfaSetupScreen extends StatefulWidget {
  const MfaSetupScreen({super.key, required this.mfaToken});
  final String mfaToken;

  @override
  State<MfaSetupScreen> createState() => _MfaSetupScreenState();
}

class _MfaSetupScreenState extends State<MfaSetupScreen> {
  final _code = TextEditingController();
  MfaSetupInfo? _info;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final info = await context.read<SessionController>().auth.mfaSetup(widget.mfaToken);
      if (mounted) setState(() => _info = info);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    try {
      final codes = await session.auth.mfaConfirm(widget.mfaToken, _code.text);
      await nav.pushReplacement(MaterialPageRoute<void>(builder: (_) => BackupCodesScreen(codes: codes)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _grouped(String secret) =>
      [for (var i = 0; i < secret.length; i += 4) secret.substring(i, i + 4 > secret.length ? secret.length : i + 4)]
          .join(' ');

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sécuriser votre compte')),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        const Text(
          'Votre compte protège les données de vos clients. En plus du mot de passe, un code à 6 chiffres '
          'changeant toutes les 30 secondes vous sera demandé.',
        ),
        const SizedBox(height: 12),
        Text('1. Installez une application d\'authentification', style: t.titleMedium),
        const Text('Par exemple Aegis (Android) ou FreeOTP, gratuites et libres.'),
        const SizedBox(height: 12),
        Text('2. Ajoutez votre compte LAMAALAM', style: t.titleMedium),
        if (info == null && _busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
        if (info != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () async {
              final ok = await launchUrl(Uri.parse(info.otpauthUri), mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                showToast(context, 'Aucune application d\'authentification trouvée : saisissez la clé à la main.');
              }
            },
            child: const Text('Ouvrir dans l\'application d\'authentification'),
          ),
          const SizedBox(height: 8),
          const Text('Ou saisissez cette clé à la main :'),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: SelectableText(_grouped(info.secret), style: t.titleMedium?.copyWith(fontFamily: 'monospace'))),
            IconButton(
              tooltip: 'Copier la clé',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: info.secret));
                showToast(context, 'Clé copiée.');
              },
            ),
          ]),
          const SizedBox(height: 12),
          Text('3. Saisissez le code affiché', style: t.titleMedium),
          const SizedBox(height: 8),
          _CodeField(controller: _code, onSubmitted: (_) => _confirm()),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Activer')),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          AlertBox(
            _error!,
            kind: AlertKind.error,
            action: info == null ? TextButton(onPressed: _start, child: const Text('Réessayer')) : null,
          ),
        ],
      ]),
    );
  }
}

/// Codes de secours, affichés une seule fois.
class BackupCodesScreen extends StatefulWidget {
  const BackupCodesScreen({super.key, required this.codes});
  final List<String> codes;

  @override
  State<BackupCodesScreen> createState() => _BackupCodesScreenState();
}

class _BackupCodesScreenState extends State<BackupCodesScreen> {
  bool _saved = false;
  bool _busy = false;
  String? _error;

  Future<void> _continue() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final session = context.read<SessionController>();
    final nav = Navigator.of(context);
    try {
      await session.completeLogin();
      nav.popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: Scaffold(
          appBar: AppBar(title: const Text('Codes de secours'), automaticallyImplyLeading: false),
          body: ListView(padding: const EdgeInsets.all(24), children: [
            const AlertBox(
              'Notez ces 10 codes sur papier et rangez-les en lieu sûr. Ils permettent de vous connecter si vous perdez '
              'votre téléphone. Ils ne seront plus jamais affichés.',
              kind: AlertKind.warning,
            ),
            const SizedBox(height: 16),
            Wrap(spacing: 16, runSpacing: 8, children: [
              for (final c in widget.codes)
                SelectableText(c, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontFamily: 'monospace')),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.codes.join('\n')));
                showToast(context, 'Codes copiés. Ne les collez pas dans une messagerie.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copier les codes'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _saved,
              onChanged: (v) => setState(() => _saved = v ?? false),
              title: const Text('J\'ai noté mes codes de secours en lieu sûr'),
            ),
            FilledButton(onPressed: _saved && !_busy ? _continue : null, child: const Text('Continuer')),
            if (_error != null) ...[const SizedBox(height: 12), AlertBox(_error!, kind: AlertKind.error)],
          ]),
        ),
      );
}
