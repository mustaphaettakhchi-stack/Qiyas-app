import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../widgets/common.dart';

const _roleLabels = {'admin': 'Administrateur', 'collaborator': 'Collaborateur', 'client': 'Client'};

/// Gestion de l'équipe (administrateur) : membres, invitations, suspension, rôles.
/// Toutes les données viennent du serveur ; ce dernier vérifie les droits.
class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _invitations = [];
  bool _loading = true;
  String? _error;

  ApiClient get _api => context.read<SessionController>().api;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await _api.get('/users') as List;
      final invitations = await _api.get('/invitations') as List;
      if (!mounted) return;
      setState(() {
        _users = users.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _invitations = invitations.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    await _load();
  }

  Future<void> _invite() async {
    final result = await showDialog<Map<String, String>>(context: context, builder: (_) => const _InviteDialog());
    if (result == null || !mounted) return;
    try {
      final inv = Map<String, dynamic>.from(await _api.post('/invitations', result) as Map);
      if (!mounted) return;
      await showInvitationLink(
        context,
        'Invitation créée',
        inv['email_sent'] == true
            ? 'Un e-mail a été envoyé à ${inv['email']}. Si besoin, transmettez aussi ce lien (valable 72 heures) :'
            : 'Aucun e-mail n\'a été envoyé (messagerie non configurée sur le serveur). '
                  'Transmettez ce lien à ${inv['email']} (valable 72 heures) :',
        inv['invitation_url'] as String,
      );
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    }
    await _load();
  }

  Future<void> _userActions(Map<String, dynamic> u) async {
    final me = context.read<SessionController>().user;
    final id = u['id'] as String;
    final suspended = u['status'] == 'suspended';
    final isAdmin = (u['roles'] as List).contains('admin');
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(u['full_name'] as String), subtitle: Text(u['email'] as String)),
            if (!(u['roles'] as List).contains('client'))
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: Text(isAdmin ? 'Passer collaborateur' : 'Passer administrateur'),
                onTap: () => Navigator.pop(c, 'role'),
              ),
            if (id != me?.id)
              ListTile(
                leading: const Icon(Icons.password),
                title: const Text('Nouveau mot de passe'),
                subtitle: const Text('Mot de passe oublié : crée un lien à transmettre'),
                onTap: () => Navigator.pop(c, 'password'),
              ),
            ListTile(
              leading: Icon(suspended ? Icons.lock_open : Icons.block),
              title: Text(suspended ? 'Réactiver le compte' : 'Suspendre le compte'),
              onTap: () => Navigator.pop(c, 'status'),
            ),
            if (id != me?.id)
              ListTile(
                leading: const Icon(Icons.phonelink_erase),
                title: const Text('Réinitialiser la double authentification'),
                subtitle: const Text('Téléphone perdu ou changé'),
                onTap: () => Navigator.pop(c, 'mfa'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'role':
        final role = isAdmin ? 'collaborator' : 'admin';
        if (await confirm(
          context,
          'Changer le profil ?',
          '${u['full_name']} deviendra ${_roleLabels[role]}. '
              'Ses sessions en cours seront fermées.',
          ok: 'Changer',
        )) {
          await _run(() => _api.patch('/users/$id', {'role': role}), 'Profil modifié.');
        }
      case 'status':
        final status = suspended ? 'active' : 'suspended';
        if (await confirm(
          context,
          suspended ? 'Réactiver ?' : 'Suspendre ?',
          suspended
              ? '${u['full_name']} pourra de nouveau se connecter.'
              : '${u['full_name']} sera déconnecté immédiatement de tous ses appareils.',
          ok: 'Confirmer',
        )) {
          await _run(() => _api.patch('/users/$id', {'status': status}), 'Compte mis à jour.');
        }
      case 'password':
        if (!await confirm(
          context,
          'Créer un lien de nouveau mot de passe ?',
          'Vérifiez l\'identité de ${u['full_name']} avant de lui transmettre le lien. '
              'Ses sessions seront fermées quand il l\'utilisera ; la double authentification reste exigée.',
          ok: 'Créer le lien',
        )) {
          return;
        }
        try {
          final r = Map<String, dynamic>.from(await _api.post('/users/$id/password-reset') as Map);
          if (!mounted) return;
          await showInvitationLink(
            context,
            'Lien de nouveau mot de passe',
            'Transmettez ce lien à ${u['full_name']} (valable 24 heures, une seule utilisation) :',
            r['reset_url'] as String,
          );
        } on ApiException catch (e) {
          if (mounted) showToast(context, e.message);
        }
      case 'mfa':
        if (await confirm(
          context,
          'Réinitialiser la double authentification ?',
          '${u['full_name']} sera déconnecté et devra la reconfigurer à sa prochaine connexion. '
              'Vérifiez son identité avant de le faire.',
          ok: 'Réinitialiser',
        )) {
          await _run(() => _api.post('/users/$id/mfa/reset'), 'Double authentification réinitialisée.');
        }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Équipe')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _invite,
      icon: const Icon(Icons.person_add_alt),
      label: const Text('Inviter'),
    ),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (_loading && _users.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            AlertBox(
              _error!,
              kind: AlertKind.error,
              action: TextButton(onPressed: _load, child: const Text('Réessayer')),
            ),
          if (_users.isNotEmpty) const SectionHeader('Membres'),
          for (final u in _users)
            Card(
              child: ListTile(
                title: Text(u['full_name'] as String),
                subtitle: Text(
                  [
                    u['email'],
                    (u['roles'] as List).map((r) => _roleLabels[r] ?? r).join(', '),
                    if (u['status'] == 'suspended') 'suspendu',
                    if (u['totp_enabled'] != true) '2FA non configurée',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.more_vert),
                onTap: () => _userActions(u),
              ),
            ),
          if (_invitations.isNotEmpty) const SectionHeader('Invitations en attente'),
          for (final i in _invitations)
            Card(
              child: ListTile(
                title: Text(i['full_name'] as String),
                subtitle: Text('${i['email']} · ${_roleLabels[i['role']] ?? i['role']}'),
                trailing: IconButton(
                  tooltip: 'Annuler l\'invitation',
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    if (await confirm(
                      context,
                      'Annuler l\'invitation ?',
                      'Le lien envoyé ne fonctionnera plus.',
                      ok: 'Annuler l\'invitation',
                    )) {
                      await _run(() => _api.delete('/invitations/${i['id']}'), 'Invitation annulée.');
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  String _role = 'collaborator';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Inviter un membre'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nom complet'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Adresse e-mail'),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'collaborator', label: Text('Collaborateur')),
              ButtonSegment(value: 'admin', label: Text('Administrateur')),
            ],
            selected: {_role},
            onSelectionChanged: (s) => setState(() => _role = s.first),
          ),
          if (_error != null) ...[const SizedBox(height: 8), AlertBox(_error!, kind: AlertKind.error)],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
      FilledButton(
        onPressed: () {
          final email = _email.text.trim();
          if (_name.text.trim().isEmpty || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
            setState(() => _error = 'Renseignez le nom et une adresse e-mail valide.');
            return;
          }
          Navigator.pop(context, {'full_name': _name.text.trim(), 'email': email, 'role': _role});
        },
        child: const Text('Inviter'),
      ),
    ],
  );
}

/// Lien d'invitation à transmettre (affiché aussi quand l'e-mail est parti).
Future<void> showInvitationLink(BuildContext context, String title, String intro, String url) => showDialog<void>(
  context: context,
  builder: (c) => AlertDialog(
    title: Text(title),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(intro),
        const SizedBox(height: 8),
        SelectableText(url),
        const SizedBox(height: 8),
        const Text('Lien personnel, utilisable une seule fois. Transmettez-le uniquement à la personne concernée.'),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () {
          Clipboard.setData(ClipboardData(text: url));
          Navigator.pop(c);
          showToast(context, 'Lien copié.');
        },
        child: const Text('Copier le lien'),
      ),
      FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer')),
    ],
  ),
);
