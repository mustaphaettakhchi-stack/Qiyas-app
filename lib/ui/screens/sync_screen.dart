import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/app_state.dart';
import '../../domain/models.dart';
import '../../sync/sync_engine.dart';
import '../widgets/common.dart';

/// État de la synchronisation, conflits à arbitrer et envois refusés.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final engine = context.watch<SyncEngine>();
    final t = Theme.of(context).textTheme;
    final last = s.data.lastSyncAt;
    final rejectedClients = s.data.clients.where((c) => c.syncError != null).toList();
    final rejectedProjects = s.data.projects.where((p) => p.syncError != null).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Synchronisation')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(last == null ? 'Jamais synchronisé.' : 'Dernière synchronisation : ${frDate(last)} à '
            '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}'),
        Text('${s.pendingCount} fiche(s) en attente d\'envoi.', style: t.bodySmall),
        if (engine.lastError != null) ...[
          const SizedBox(height: 8),
          AlertBox(engine.lastError!, kind: engine.phase == SyncPhase.offline ? AlertKind.warning : AlertKind.error),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: engine.phase == SyncPhase.running ? null : engine.syncNow,
          icon: const Icon(Icons.sync),
          label: const Text('Synchroniser maintenant'),
        ),
        const SizedBox(height: 12),
        const AlertBox(
          'Sont partagés avec le serveur : les clients, les projets, leurs pièces, les devis et la bibliothèque. '
          'Les photos restent sur ce téléphone, sauf celles partagées dans l\'espace client.',
        ),
        if (s.data.conflicts.isNotEmpty) ...[
          const SectionHeader('Conflits à arbitrer'),
          for (final c in List.of(s.data.conflicts)) _ConflictCard(conflict: c),
        ],
        if (rejectedClients.isNotEmpty || rejectedProjects.isNotEmpty) ...[
          const SectionHeader('Envois refusés'),
          const Text('Corrigez la fiche : elle sera renvoyée automatiquement.'),
          for (final c in rejectedClients)
            Card(child: ListTile(title: Text('Client · ${c.displayName}'), subtitle: Text(c.syncError!))),
          for (final p in rejectedProjects)
            Card(child: ListTile(title: Text('Projet · ${s.clientName(p)}'), subtitle: Text(p.syncError!))),
        ],
      ]),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.conflict});
  final SyncConflict conflict;

  static const _clientFields = {
    'display_name': 'Nom',
    'type': 'Type',
    'phone': 'Téléphone',
    'email': 'E-mail',
    'address': 'Adresse',
    'city': 'Ville',
    'ice': 'ICE',
    'notes': 'Notes',
    'consent_at': 'Consentement',
  };

  static const _projectFields = {
    'name': 'Nom du projet',
    'client_id': 'Client',
    'project_type': 'Nature des travaux',
    'property_kind': 'Type de bien',
    'status': 'Statut',
    'site_address': 'Adresse du chantier',
    'site_city': 'Ville',
    'visit_date': 'Date de visite',
    'budget_cents': 'Budget',
    'description': 'Description',
    'notes': 'Notes',
    'manager_id': 'Responsable',
  };

  static const _roomFields = {
    'name': 'Nom de la pièce',
    'height_m': 'Hauteur',
    'walls': 'Murs',
    'openings': 'Ouvertures',
    'plan_x': 'Position sur le plan',
  };

  String _show(AppState s, String key, Object? v) {
    if (v == null || v == '') return '—';
    return switch (key) {
      'walls' => (v as List).map((w) => fmt2(((w as Map)['length'] as num).toDouble())).join(' / '),
      'openings' => '${(v as List).length} ouverture(s)',
      'height_m' => '${fmt2((v as num).toDouble())} m',
      'client_id' => s.client(v as String)?.displayName ?? 'autre client',
      'project_type' => kProjectTypes[v] ?? '$v',
      'property_kind' => kPropertyKinds[v] ?? '$v',
      'status' => kProjectStatuses[v] ?? '$v',
      'type' => kClientTypes[v] ?? '$v',
      'budget_cents' => dh(v as int),
      'consent_at' => 'donné',
      'manager_id' => 'défini',
      _ => '$v',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final engine = context.read<SyncEngine>();
    final isClient = conflict.entity == 'clients';
    final isRoom = conflict.entity == 'rooms';
    final roomProject = isRoom ? s.data.projects.where((p) => p.rooms.any((r) => r.id == conflict.id)).firstOrNull : null;
    final local = isClient
        ? s.data.clients.where((c) => c.id == conflict.id).firstOrNull?.toServer()
        : isRoom
            ? roomProject?.rooms.firstWhere((r) => r.id == conflict.id).toServer(roomProject.id)
            : s.data.projects.where((p) => p.id == conflict.id).firstOrNull?.toServer();
    final localDeleted = isRoom && local == null;
    final serverDeleted = conflict.server['deleted'] == true;
    final serverData = Map<String, dynamic>.from(conflict.server['data'] as Map? ?? {});
    final fields = isClient ? _clientFields : (isRoom ? _roomFields : _projectFields);
    final title = isClient
        ? 'Client · ${local?['display_name'] ?? serverData['display_name'] ?? ''}'
        : isRoom
            ? 'Pièce · ${local?['name'] ?? serverData['name'] ?? ''}'
            : 'Projet · ${conflict.server['reference'] ?? ''} ${local?['name'] ?? ''}';
    String norm(String key, Object? v) => key == 'walls' || key == 'openings' ? _show(s, key, v) : '$v';
    final diffs = [
      for (final e in fields.entries)
        if (local != null && !serverDeleted && norm(e.key, local[e.key]) != norm(e.key, serverData[e.key])) e,
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          Text(conflict.reason),
          const SizedBox(height: 8),
          if (serverDeleted) const Text('Sur le serveur : supprimé.'),
          if (localDeleted) const Text('Sur ce téléphone : supprimée.'),
          for (final e in diffs) ...[
            Text(e.value, style: Theme.of(context).textTheme.labelLarge),
            Text('Ce téléphone : ${_show(s, e.key, local![e.key])}'),
            Text('Serveur : ${_show(s, e.key, serverData[e.key])}'),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: () async {
                if (await confirm(context, 'Garder la version du serveur ?',
                    serverDeleted
                        ? 'La fiche sera supprimée de ce téléphone, avec ses pièces, photos et devis locaux.'
                        : 'Vos modifications sur ce téléphone seront remplacées.',
                    ok: 'Garder le serveur')) {
                  engine.keepServer(conflict);
                }
              },
              child: const Text('Garder le serveur'),
            ),
            FilledButton(
              onPressed: () async {
                if (await confirm(context, 'Garder votre version ?',
                    serverDeleted
                        ? 'La fiche sera restaurée sur le serveur.'
                        : 'La version du serveur sera remplacée par la vôtre.',
                    ok: 'Garder la mienne')) {
                  engine.keepMine(conflict);
                }
              },
              child: const Text('Garder la mienne'),
            ),
          ]),
        ]),
      ),
    );
  }
}
