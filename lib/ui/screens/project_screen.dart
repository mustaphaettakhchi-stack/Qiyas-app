import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
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
        Row(children: [
          Expanded(child: EditField(key: ValueKey('client-${p.id}'), label: 'Client', value: p.client, onChanged: (v) => edit(() => p.client = v))),
          const SizedBox(width: 12),
          Expanded(child: EditField(key: ValueKey('tel-${p.id}'), label: 'Téléphone', value: p.phone, keyboardType: TextInputType.phone, onChanged: (v) => edit(() => p.phone = v))),
        ]),
        EditField(key: ValueKey('addr-${p.id}'), label: 'Adresse du chantier', value: p.address, onChanged: (v) => edit(() => p.address = v)),
        EditField(key: ValueKey('city-${p.id}'), label: 'Ville', value: p.city, onChanged: (v) => edit(() => p.city = v)),
        EditField(key: ValueKey('notes-${p.id}'), label: 'Notes', value: p.notes, maxLines: 3, onChanged: (v) => edit(() => p.notes = v)),
        SectionHeader(
          'Photos du chantier',
          trailing: TextButton.icon(
            onPressed: () async {
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
              title: Text(q.number),
              subtitle: Text(frDate(q.date)),
              trailing: StatusPill(q.status),
              onTap: () => open(QuoteScreen(projectId: p.id, quoteId: q.id)),
            ),
        ],
      ]),
    );
  }
}
