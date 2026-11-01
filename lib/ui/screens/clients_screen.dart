import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/app_state.dart';
import '../../domain/models.dart';
import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../widgets/common.dart';
import 'project_screen.dart';
import 'team_screen.dart';

bool _matches(Client c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final digits = q.replaceAll(RegExp(r'\D'), '');
  return '${c.displayName} ${c.city} ${c.email}'.toLowerCase().contains(q) ||
      (digits.length >= 3 && c.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
}

/// Liste des clients.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.activeClients.where((c) => _matches(c, _query)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Clients'), actions: const [SyncBadge()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final c = s.createClient();
          Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ClientScreen(clientId: c.id)));
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Nouveau client'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Nom, ville ou téléphone'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          if (list.isEmpty) const AlertBox('Aucun client. Ajoutez-en un avec « Nouveau client ».'),
          for (final c in list)
            Card(
              child: ListTile(
                title: Text(c.displayName.isEmpty ? 'Nom à renseigner' : c.displayName),
                subtitle: Text([c.city, c.phone, '${s.projectsOf(c).length} projet(s)'].where((x) => x.isNotEmpty).join(' · ')),
                trailing: c.syncError != null ? const Icon(Icons.error_outline) : null,
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ClientScreen(clientId: c.id))),
              ),
            ),
        ],
      ),
    );
  }
}

/// Fiche client.
class ClientScreen extends StatelessWidget {
  const ClientScreen({super.key, required this.clientId});
  final String clientId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    final c = s.client(clientId);
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Client introuvable.')),
      );
    }
    void edit(VoidCallback f) => s.mutate(f, client: c);
    final projects = s.projectsOf(c);
    final canDelete = projects.isEmpty && (c.serverVersion == null || (session.user?.isAdmin ?? false));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche client'),
        actions: [
          const SyncBadge(),
          if (canDelete)
            IconButton(
              tooltip: 'Supprimer la fiche',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Supprimer ce client ?', 'La fiche sera supprimée pour toute l\'équipe.', ok: 'Supprimer')) {
                  s.deleteClient(c);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (c.syncError != null) ...[AlertBox('Envoi refusé : ${c.syncError}', kind: AlertKind.error), const SizedBox(height: 8)],
          SegmentedButton<String>(
            segments: [for (final e in kClientTypes.entries) ButtonSegment(value: e.key, label: Text(e.value))],
            selected: {c.type},
            onSelectionChanged: (v) => edit(() => c.type = v.first),
          ),
          EditField(
            key: ValueKey('cn-${c.id}'),
            label: c.type == 'company' ? 'Raison sociale' : 'Nom et prénom',
            value: c.displayName,
            onChanged: (v) => edit(() => c.displayName = v),
          ),
          EditField(
            key: ValueKey('cp-${c.id}'),
            label: 'Téléphone',
            value: c.phone,
            keyboardType: TextInputType.phone,
            onChanged: (v) => edit(() => c.phone = v),
          ),
          EditField(
            key: ValueKey('ce-${c.id}'),
            label: 'E-mail (facultatif)',
            value: c.email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (v) => edit(() => c.email = v),
          ),
          EditField(key: ValueKey('ca-${c.id}'), label: 'Adresse', value: c.address, onChanged: (v) => edit(() => c.address = v)),
          EditField(key: ValueKey('cv-${c.id}'), label: 'Ville', value: c.city, onChanged: (v) => edit(() => c.city = v)),
          if (c.type == 'company')
            EditField(
              key: ValueKey('ci-${c.id}'),
              label: 'ICE (15 chiffres)',
              value: c.ice,
              keyboardType: TextInputType.number,
              maxLength: 15,
              onChanged: (v) => edit(() => c.ice = v),
            ),
          EditField(key: ValueKey('co-${c.id}'), label: 'Notes', value: c.notes, maxLines: 3, onChanged: (v) => edit(() => c.notes = v)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Consentement du client'),
            subtitle: const Text(kConsentText),
            value: c.hasConsent,
            onChanged: (v) => edit(() {
              c.consentAt = v ? DateTime.now() : null;
              c.consentTextVersion = v ? Client.currentConsentVersion : '';
            }),
          ),
          if (c.hasConsent) Text('Recueilli le ${frDate(c.consentAt!)}.', style: Theme.of(context).textTheme.bodySmall),
          if (!session.isDemo && (session.user?.isAdmin ?? false)) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: c.serverVersion == null
                  ? () => showToast(context, 'Synchronisez d\'abord cette fiche client.')
                  : () => _inviteClient(context, c),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Inviter dans l\'espace client'),
            ),
          ],
          SectionHeader('Projets · ${projects.length}'),
          for (final p in projects)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p.name.isEmpty ? (kProjectTypes[p.projectType] ?? 'Projet') : p.name),
              subtitle: Text([p.reference ?? 'référence à l\'envoi', kProjectStatuses[p.status] ?? p.status].join(' · ')),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => ProjectScreen(projectId: p.id))),
            ),
        ],
      ),
    );
  }
}

/// Crée l'accès du client à son espace en lecture seule (rôle « client » rattaché à cette fiche).
Future<void> _inviteClient(BuildContext context, Client c) async {
  final email = TextEditingController(text: c.email);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Inviter dans l\'espace client'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${c.displayName} pourra consulter ses projets : devis envoyés, photos partagées, étapes, messages. '
            'Aucune modification possible.',
          ),
          const SizedBox(height: 8),
          TextField(
            controller: email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Adresse e-mail du client'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Inviter')),
      ],
    ),
  );
  final address = email.text.trim();
  email.dispose();
  if (ok != true || !context.mounted) return;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(address)) {
    showToast(context, 'Adresse e-mail invalide.');
    return;
  }
  try {
    final inv = Map<String, dynamic>.from(
      await context.read<SessionController>().api.post('/invitations', {
            'email': address,
            'full_name': c.displayName.trim().isEmpty ? address : c.displayName.trim(),
            'role': 'client',
            'client_id': c.id,
          })
          as Map,
    );
    if (!context.mounted) return;
    await showInvitationLink(
      context,
      'Invitation créée',
      inv['email_sent'] == true
          ? 'Un e-mail a été envoyé à $address. Si besoin, transmettez aussi ce lien (valable 72 heures) :'
          : 'Aucun e-mail n\'a été envoyé (messagerie non configurée sur le serveur). Transmettez ce lien à $address (valable 72 heures) :',
      inv['invitation_url'] as String,
    );
  } on ApiException catch (e) {
    if (context.mounted) showToast(context, e.message);
  }
}

/// Choix du client d'un projet : recherche ou création. Renvoie l'identifiant choisi.
Future<String?> pickClient(BuildContext context) =>
    showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => const _ClientPicker());

class _ClientPicker extends StatefulWidget {
  const _ClientPicker();

  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.activeClients.where((c) => _matches(c, _query.text)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Client (nom, ville ou téléphone)'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt),
              title: Text(_query.text.trim().isEmpty ? 'Nouveau client' : 'Nouveau client « ${_query.text.trim()} »'),
              onTap: () => Navigator.pop(context, s.createClient(name: _query.text.trim()).id),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final c in list)
                    ListTile(
                      title: Text(c.displayName.isEmpty ? 'Nom à renseigner' : c.displayName),
                      subtitle: Text([c.city, c.phone].where((x) => x.isNotEmpty).join(' · ')),
                      onTap: () => Navigator.pop(context, c.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
