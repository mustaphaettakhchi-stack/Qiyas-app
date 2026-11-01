import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/labels.dart';
import '../../data/app_state.dart';
import '../../data/client_space.dart';
import '../../domain/dashboard.dart';
import '../../domain/models.dart';
import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../../sync/sync_engine.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import 'clients_screen.dart';
import 'messages_screen.dart';
import 'project_screen.dart';
import 'quote_screen.dart';
import 'sync_screen.dart';

const kActivityLabels = {
  'project.create': 'Projet créé',
  'project.delete': 'Projet supprimé',
  'client.create': 'Client créé',
  'client.delete': 'Client supprimé',
  'metre.validate': 'Métré validé',
  'estimate.create': 'Devis préparé',
  'estimate.validate': 'Devis validé',
  'estimate.send': 'Devis envoyé',
  'estimate.accept': 'Devis accepté',
  'estimate.refuse': 'Devis refusé',
  'invitation.accept': 'Nouveau membre',
  'library.import': 'Bibliothèque importée',
  'message.post': 'Message',
  'file.share': 'Photo partagée avec le client',
};

/// Accueil : indicateurs, raccourcis, actions à mener, derniers projets, dernières opérations.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    final isAdmin = (session.user?.isAdmin ?? false) || session.isDemo;
    final stats = dashboardStats(s.data);
    final todos = todoItems(s.data, isAdmin: isAdmin, clientName: s.clientName);
    final recent = s.activeProjects.take(5).toList();
    final t = Theme.of(context).textTheme;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));

    Future<void> newProject() async {
      final clientId = await pickClient(context);
      if (clientId == null || !context.mounted) return;
      open(ProjectScreen(projectId: s.createProject(clientId: clientId).id));
    }

    Future<void> newQuote() async {
      final projects = s.activeProjects;
      if (projects.isEmpty) {
        showToast(context, 'Créez d\'abord un projet.');
        return;
      }
      final p = await showModalBottomSheet<Project>(
        context: context,
        isScrollControlled: true,
        builder: (c) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Devis pour quel projet ?')),
              for (final p in projects)
                ListTile(
                  title: Text(s.clientName(p)),
                  subtitle: Text([p.reference ?? 'référence à l\'envoi', p.city].where((x) => x.isNotEmpty).join(' · ')),
                  onTap: () => Navigator.pop(c, p),
                ),
            ]),
          ),
        ),
      );
      if (p != null && context.mounted) {
        final q = s.draftQuoteFor(p);
        open(QuoteScreen(projectId: p.id, quoteId: q.id));
      }
    }

    void openTodo(TodoItem item) {
      if (item.kind == TodoKind.syncIssue) return open(const SyncScreen());
      final p = item.projectId;
      if (p == null) return;
      if (item.quoteId != null) return open(QuoteScreen(projectId: p, quoteId: item.quoteId!));
      open(ProjectScreen(projectId: p));
    }

    final accepted = stats.acceptedTtcYear.entries.map((e) => money(e.value, e.key)).join(' + ');

    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const LogoTile(size: 32),
          const SizedBox(width: 10),
          Flexible(child: Text(session.user?.fullName ?? 'Accueil', overflow: TextOverflow.ellipsis)),
        ]),
        actions: const [SyncBadge()],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<SyncEngine>().syncNow(),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // En tête : un client qui attend une réponse passe avant les indicateurs.
          const _ClientMessages(),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.9,
            children: [
              _Kpi(label: 'Chantiers actifs', value: stats.activeSites, icon: Icons.construction),
              _Kpi(label: 'Prospects', value: stats.prospects, icon: Icons.person_search_outlined),
              _Kpi(label: 'Devis à valider', value: stats.quotesToValidate, icon: Icons.edit_note),
              _Kpi(label: 'Devis à envoyer', value: stats.quotesToSend, icon: Icons.outgoing_mail),
              _Kpi(label: 'En attente de réponse', value: stats.quotesWaiting, icon: Icons.hourglass_bottom),
              _Kpi(label: 'Devis acceptés', value: stats.quotesAccepted, icon: Icons.verified_outlined),
            ],
          ),
          if (accepted.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Accepté en ${DateTime.now().year} : $accepted TTC', style: t.titleSmall),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: FilledButton.icon(onPressed: newProject, icon: const Icon(Icons.add_home_work_outlined), label: const Text('Nouveau projet'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: newQuote, icon: const Icon(Icons.request_quote_outlined), label: const Text('Nouveau devis'))),
          ]),
          SectionHeader('À faire · ${todos.length}'),
          if (todos.isEmpty) Text('Rien en attente.', style: t.bodySmall),
          for (final item in todos.take(12))
            Card(
              child: ListTile(
                leading: Icon(_todoIcon(item.kind), color: Theme.of(context).colorScheme.primary),
                title: Text(item.title),
                subtitle: item.detail.isEmpty ? null : Text(item.detail),
                onTap: () => openTodo(item),
              ),
            ),
          if (todos.length > 12) Text('… et ${todos.length - 12} autre(s).', style: t.bodySmall),
          const SectionHeader('Derniers projets'),
          if (recent.isEmpty) Text('Aucun projet.', style: t.bodySmall),
          for (final p in recent)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.clientName(p)),
              subtitle: Text([p.reference ?? 'référence à l\'envoi', kProjectStatuses[p.status] ?? p.status, frDate(p.updatedAt)].join(' · ')),
              onTap: () => open(ProjectScreen(projectId: p.id)),
            ),
          const SectionHeader('Dernières opérations'),
          const _Activity(),
        ]),
      ),
    );
  }
}

IconData _todoIcon(TodoKind k) => switch (k) {
      TodoKind.validateQuote => Icons.edit_note,
      TodoKind.numberPending => Icons.sync,
      TodoKind.sendQuote => Icons.outgoing_mail,
      TodoKind.followUp => Icons.phone_callback_outlined,
      TodoKind.metreStale => Icons.straighten,
      TodoKind.visit => Icons.event_outlined,
      TodoKind.syncIssue => Icons.sync_problem,
    };

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, required this.icon});
  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Fils où un client attend une réponse. Relus à chaque synchronisation (dont le
/// geste « tirer pour actualiser ») et au retour du fil ; rien n'apparaît hors connexion.
class _ClientMessages extends StatefulWidget {
  const _ClientMessages();

  @override
  State<_ClientMessages> createState() => _ClientMessagesState();
}

class _ClientMessagesState extends State<_ClientMessages> {
  List<UnreadThread> _threads = const [];
  DateTime? _loadedFor;
  bool _started = false;
  bool _loading = false;

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    try {
      final t = await ClientSpaceApi(context.read<SessionController>().api).unreadThreads();
      if (mounted) setState(() => _threads = t);
    } on ApiException {
      // Hors connexion ou serveur indisponible : la section reste telle quelle.
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final lastSync = context.select<AppState, DateTime?>((s) => s.data.lastSyncAt);
    if (session.isDemo || !session.verifiedOnline) return const SizedBox.shrink();
    // Première lecture, puis une nouvelle après chaque synchronisation.
    if (!_started || _loadedFor != lastSync) {
      _started = true;
      _loadedFor = lastSync;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    if (_threads.isEmpty) return const SizedBox.shrink();
    final total = _threads.fold(0, (n, t) => n + t.unread);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader('Messages de clients · $total'),
        for (final t in _threads)
          Card(
            child: ListTile(
              leading: Badge(label: Text('${t.unread}'), child: const Icon(Icons.chat_bubble_outline)),
              title: Text(t.clientName.isEmpty ? 'Client' : t.clientName),
              subtitle: Text(
                [t.projectReference ?? t.projectName, 'dernier message le ${frDateTime(t.lastAt)}'].where((x) => x.isNotEmpty).join(' · '),
              ),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => MessagesScreen(
                      projectId: t.projectId,
                      title: 'Messages · ${t.clientName.isEmpty ? 'Client' : t.clientName}',
                      asClient: false,
                    ),
                  ),
                );
                await _load();
              },
            ),
          ),
      ],
    );
  }
}

/// Dernières opérations, lues dans le journal d'audit du serveur (connexion requise).
class _Activity extends StatefulWidget {
  const _Activity();

  @override
  State<_Activity> createState() => _ActivityState();
}

class _ActivityState extends State<_Activity> {
  List<Map<String, dynamic>>? _rows;
  String? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionController>();
    if (_rows == null && _error == null && !_loading && session.verifiedOnline && !session.isDemo) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await context.read<SessionController>().api.get('/dashboard/activity?limit=15') as List;
      if (mounted) setState(() => _rows = [for (final x in r) Map<String, dynamic>.from(x as Map)]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    if (session.isDemo || !session.verifiedOnline) {
      return Text('Disponible avec une connexion au serveur.', style: t.bodySmall);
    }
    if (_loading && _rows == null) return const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
    if (_error != null) return AlertBox(_error!, kind: AlertKind.error, action: TextButton(onPressed: _load, child: const Text('Réessayer')));
    final rows = _rows ?? const [];
    if (rows.isEmpty) return Text('Aucune opération récente.', style: t.bodySmall);
    return Column(children: [
      for (final r in rows)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text([
            kActivityLabels[r['action']] ?? r['action'],
            if ((r['details'] as Map)['reference'] != null) (r['details'] as Map)['reference'],
          ].join(' · ')),
          subtitle: Text([
            frDate(DateTime.parse(r['occurred_at'] as String).toLocal()),
            r['actor_name'],
            if (r['project_reference'] != null) r['project_reference'],
          ].where((x) => '$x'.isNotEmpty).join(' · ')),
        ),
      TextButton(onPressed: _load, child: const Text('Actualiser')),
    ]);
  }
}
