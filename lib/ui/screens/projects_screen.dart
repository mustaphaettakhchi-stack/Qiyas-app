import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';
import 'project_screen.dart';

/// E3 · Liste des projets (accueil).
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

enum _Filter { all, survey, draft, sent, accepted, refused }

const _filterLabels = {
  _Filter.all: 'Tous',
  _Filter.survey: 'Relevé',
  _Filter.draft: 'Brouillon',
  _Filter.sent: 'Envoyés',
  _Filter.accepted: 'Acceptés',
  _Filter.refused: 'Refusés',
};

class _ProjectsScreenState extends State<ProjectsScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;

  bool _matches(Project p) {
    final st = p.lastQuote?.status;
    final okFilter = switch (_filter) {
      _Filter.all => true,
      _Filter.survey => st == null,
      _Filter.draft => st == QuoteStatus.draft,
      _Filter.sent => st == QuoteStatus.sent,
      _Filter.accepted => st == QuoteStatus.accepted,
      _Filter.refused => st == QuoteStatus.refused,
    };
    final q = _query.trim().toLowerCase();
    final okQuery = q.length < 3 || '${p.client} ${p.city}'.toLowerCase().contains(q);
    return okFilter && okQuery;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final list = s.activeProjects.where(_matches).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Projets'), actions: const [SyncBadge()]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final p = s.createProject();
          Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p.id)));
        },
        icon: const Icon(Icons.add),
        label: const Text('Nouveau projet'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher un client (3 lettres min.)'),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in _Filter.values)
            ChoiceChip(label: Text(_filterLabels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
        ]),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const AlertBox('Aucun projet ne correspond. Créez votre premier relevé avec le bouton « Nouveau projet ».'),
        for (final p in list) _ProjectCard(p: p, vat: s.company.vatPercent),
      ]),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.p, required this.vat});
  final Project p;
  final double vat;

  @override
  Widget build(BuildContext context) {
    final q = p.lastQuote;
    final ttc = q == null ? null : quoteTotals(p, q, vat).ttc;
    final t = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProjectScreen(projectId: p.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(p.client.isEmpty ? 'Client à renseigner' : p.client, style: t.titleMedium)),
              StatusPill(q?.status),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: Text(
                  '${p.city} · ${frDate(p.updatedAt)}${p.synced ? '' : ' · non synchronisé'}',
                  style: t.bodySmall,
                ),
              ),
              Text(ttc == null ? '—' : '${dh(ttc)} TTC', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ]),
        ),
      ),
    );
  }
}
