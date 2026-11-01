import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'clients_screen.dart';
import 'metre_screen.dart';
import 'plan_screen.dart';
import 'quote_screen.dart';
import 'room_screen.dart';

/// E4 · Fiche projet.
class ProjectScreen extends StatelessWidget {
  const ProjectScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    if (p == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Projet introuvable.')));
    }
    void edit(VoidCallback f) => s.mutate(f, touch: p);
    void meta(VoidCallback f) => s.mutate(f, touch: p, meta: true);
    final client = s.clientOf(p);
    final m = projectMeasures(p);
    final hasRooms = p.rooms.isNotEmpty;

    void open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche projet'),
        actions: [
          const SyncBadge(),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'dup') {
                final c = s.duplicateProject(p);
                showToast(context, 'Projet dupliqué, sans ses devis.');
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: c.id)));
              } else if (v == 'arch') {
                if (await confirm(context, 'Archiver ce projet ?', 'Il n\'apparaîtra plus dans la liste.', ok: 'Archiver')) {
                  s.archiveProject(p);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'dup', child: Text('Dupliquer le projet')),
              PopupMenuItem(value: 'arch', child: Text('Archiver')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (p.syncError != null) ...[AlertBox('Envoi refusé : ${p.syncError}', kind: AlertKind.error), const SizedBox(height: 8)],
        Text(p.reference ?? 'Référence attribuée à la première synchronisation', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(s.clientName(p)),
            subtitle: Text(client == null
                ? 'Touchez pour choisir le client'
                : [client.phone, client.city].where((x) => x.isNotEmpty).join(' · ')),
            trailing: TextButton(
              onPressed: () async {
                final id = await pickClient(context);
                if (id != null) meta(() => p.clientId = id);
              },
              child: const Text('Changer'),
            ),
            onTap: client == null
                ? () async {
                    final id = await pickClient(context);
                    if (id != null) meta(() => p.clientId = id);
                  }
                : () => open(ClientScreen(clientId: client.id)),
          ),
        ),
        EditField(key: ValueKey('name-${p.id}'), label: 'Nom du projet (facultatif)', value: p.name, onChanged: (v) => meta(() => p.name = v)),
        _Choice(
          label: 'Nature des travaux',
          value: p.projectType,
          options: kProjectTypes,
          onChanged: (v) => meta(() => p.projectType = v!),
        ),
        _Choice(
          label: 'Type de bien',
          value: p.propertyKind,
          options: kPropertyKinds,
          allowEmpty: true,
          onChanged: (v) => meta(() => p.propertyKind = v),
        ),
        _Choice(
          label: 'Statut',
          value: p.status,
          options: kProjectStatuses,
          onChanged: (v) => meta(() => p.status = v!),
        ),
        EditField(key: ValueKey('addr-${p.id}'), label: 'Adresse du chantier', value: p.address, onChanged: (v) => meta(() => p.address = v)),
        EditField(key: ValueKey('city-${p.id}'), label: 'Ville', value: p.city, onChanged: (v) => meta(() => p.city = v)),
        Row(children: [
          Expanded(
            child: NumField(
              label: 'Budget estimatif',
              suffix: p.currency,
              decimals: 0,
              value: (p.budgetCents ?? 0) / 100,
              onChanged: (v) => meta(() => p.budgetCents = v <= 0 ? null : (v * 100).round()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined),
              label: Text(p.visitDate == null ? 'Date de visite' : 'Visite : ${frDate(p.visitDate!)}'),
              onPressed: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: p.visitDate ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (d != null) meta(() => p.visitDate = d);
              },
            ),
          ),
        ]),
        EditField(key: ValueKey('desc-${p.id}'), label: 'Description des travaux', value: p.description, maxLines: 3, onChanged: (v) => meta(() => p.description = v)),
        EditField(key: ValueKey('notes-${p.id}'), label: 'Notes', value: p.notes, maxLines: 3, onChanged: (v) => meta(() => p.notes = v)),
        const SizedBox(height: 8),
        const AlertBox('Pièces, photos et devis : enregistrés sur ce téléphone uniquement pour l\'instant.'),
        SectionHeader(
          'Photos du chantier',
          trailing: TextButton.icon(
            onPressed: () async {
              // Photos du domicile d'un client : consentement préalable obligatoire (USER_FLOWS A2.4).
              if (client == null || !client.hasConsent) {
                showToast(context, 'Recueillez d\'abord le consentement du client sur sa fiche.');
                return;
              }
              final paths = await pickPhotos(context);
              if (paths.isNotEmpty) edit(() => p.photoPaths.addAll(paths));
            },
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Ajouter'),
          ),
        ),
        PhotoStrip(paths: p.photoPaths),
        SectionHeader(
          'Pièces · ${p.rooms.length} · ${fmt2(m.floor)} m²',
          trailing: FilledButton.tonalIcon(
            onPressed: () {
              final r = s.addRoom(p);
              open(RoomScreen(projectId: p.id, roomId: r.id));
            },
            icon: const Icon(Icons.add),
            label: const Text('Pièce'),
          ),
        ),
        if (!hasRooms) const Text('Ajoutez la première pièce pour démarrer le relevé.'),
        for (final r in p.rooms)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(r.name),
              subtitle: Text('${fmt2(r.length)} × ${fmt2(r.width)} × ${fmt2(r.height)} m · '
                  '${r.doorCount} porte(s), ${r.windowCount} fenêtre(s)'),
              trailing: Text('${fmt2(roomMeasures(r).floor)} m²'),
              onTap: () => open(RoomScreen(projectId: p.id, roomId: r.id)),
            ),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: hasRooms ? () => open(PlanScreen(projectId: p.id)) : null, child: const Text('Plan'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: hasRooms ? () => open(MetreScreen(projectId: p.id)) : null, child: const Text('Métré'))),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: hasRooms
                  ? () {
                      final q = s.draftQuoteFor(p);
                      open(QuoteScreen(projectId: p.id, quoteId: q.id));
                    }
                  : null,
              child: const Text('Devis'),
            ),
          ),
        ]),
        if (p.quotes.isNotEmpty) ...[
          const SectionHeader('Devis du projet'),
          for (final q in p.quotes.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(q.displayNumber),
              subtitle: Text(frDate(q.date)),
              trailing: StatusPill(q.status),
              onTap: () => open(QuoteScreen(projectId: p.id, quoteId: q.id)),
            ),
        ],
      ]),
    );
  }
}

/// Liste de choix compacte.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowEmpty = false,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<String?>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (allowEmpty) const DropdownMenuItem<String?>(value: null, child: Text('Non précisé')),
            for (final e in options.entries) DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
          ],
          onChanged: onChanged,
        ),
      );
}
