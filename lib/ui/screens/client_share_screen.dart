import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../data/client_space.dart';
import '../../domain/models.dart';
import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../../sync/sync_engine.dart';
import '../widgets/common.dart';
import '../widgets/photos.dart';
import 'messages_screen.dart';

/// Ce que le client voit de ce projet, et ce que l'équipe choisit de lui montrer.
///
/// Rien n'est partagé par défaut (USER_FLOWS A8.2) : chaque photo est envoyée
/// explicitement, et le partage peut être retiré à tout moment. Les PDF des devis
/// envoyés sont publiés automatiquement après synchronisation.
class ClientShareScreen extends StatefulWidget {
  const ClientShareScreen({super.key, required this.projectId});
  final String projectId;

  @override
  State<ClientShareScreen> createState() => _ClientShareScreenState();
}

class _ClientShareScreenState extends State<ClientShareScreen> {
  List<ProjectFile>? _files;
  String? _error;
  bool _busy = false;

  ClientSpaceApi get _api => ClientSpaceApi(context.read<SessionController>().api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final p = context.read<AppState>().project(widget.projectId);
    if (p == null || p.serverVersion == null) return;
    try {
      final f = await _api.projectFiles(widget.projectId);
      if (mounted) {
        setState(() {
          _files = f;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _guard(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showToast(context, done);
    } on ApiException catch (e) {
      if (mounted) showToast(context, e.message);
    } on FileSystemException {
      if (mounted) showToast(context, 'Photo introuvable sur ce téléphone.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _load();
  }

  Future<void> _sharePhoto(Project p) async {
    // Photos du domicile d'un client : consentement préalable obligatoire (USER_FLOWS A2.4).
    final client = context.read<AppState>().clientOf(p);
    if (client == null || !client.hasConsent) {
      showToast(context, 'Recueillez d\'abord le consentement du client sur sa fiche.');
      return;
    }
    final local = [...p.photoPaths, for (final r in p.rooms) ...r.photoPaths];
    final path = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(title: Text('Photo à montrer au client')),
              ListTile(
                leading: const Icon(Icons.add_a_photo_outlined),
                title: const Text('Prendre ou choisir une nouvelle photo'),
                onTap: () => Navigator.pop(c, ''),
              ),
              if (local.isNotEmpty)
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (final x in local)
                      InkWell(
                        onTap: () => Navigator.pop(c, x),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(x), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
    if (path == null || !mounted) return;
    var chosen = path;
    if (chosen.isEmpty) {
      final picked = await pickPhotos(context, multiple: false);
      if (picked.isEmpty || !mounted) return;
      chosen = picked.first;
      // La nouvelle photo rejoint aussi les photos du projet sur le téléphone.
      context.read<AppState>().mutate(() => p.photoPaths.add(chosen), touch: p);
    }
    final caption = await _askCaption();
    if (caption == null || !mounted) return;
    await _guard(
      () async => _api.uploadPhoto(p.id, await File(chosen).readAsBytes(), caption: caption),
      'Photo partagée avec le client (sans les données de localisation).',
    );
  }

  Future<String?> _askCaption() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Partager avec le client'),
        content: TextField(
          controller: ctrl,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Légende (facultative)', hintText: 'Salon avant travaux'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Partager')),
        ],
      ),
    ).whenComplete(ctrl.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final sync = context.read<SyncEngine>();
    final t = Theme.of(context).textTheme;
    final p = s.project(widget.projectId);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Projet introuvable.')),
      );
    }
    final files = _files;
    final photos = files?.where((f) => f.kind == 'photo').toList() ?? const <ProjectFile>[];
    final pdfFor = {
      for (final f in files ?? const <ProjectFile>[])
        if (f.kind == 'quote_pdf') f.quoteVersionId: f,
    };
    final sentQuotes = p.quotes
        .where((q) => !q.legacy && (q.status == QuoteStatus.sent || q.status == QuoteStatus.accepted || q.status == QuoteStatus.refused))
        .toList();
    final synced = p.serverVersion != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Espace client'),
        actions: [IconButton(tooltip: 'Actualiser', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${s.clientName(p)} · ${p.reference ?? 'projet non synchronisé'}', style: t.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Le client voit : ses projets, les devis envoyés (montants et PDF, jamais les déboursés ni la marge), '
            'les photos partagées ci-dessous, les grandes étapes et les messages. Il ne peut rien modifier.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 12),
          if (!synced)
            const AlertBox('Synchronisez d\'abord ce projet : le partage passe par le serveur.', kind: AlertKind.warning)
          else ...[
            if (_error != null)
              AlertBox(
                _error!,
                kind: AlertKind.error,
                action: TextButton(onPressed: _load, child: const Text('Réessayer')),
              ),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MessagesScreen(projectId: p.id, title: 'Messages · ${s.clientName(p)}', asClient: false),
                ),
              ),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Messages avec le client'),
            ),
            SectionHeader(
              'Photos partagées',
              trailing: TextButton.icon(
                onPressed: _busy || files == null ? null : () => _sharePhoto(p),
                icon: const Icon(Icons.ios_share),
                label: const Text('Partager'),
              ),
            ),
            Text('Le client reçoit une copie sans données de localisation ni informations de l\'appareil.', style: t.bodySmall),
            if (files == null && _error == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (files != null && photos.isEmpty) Text('Aucune photo envoyée.', style: t.bodySmall),
            for (final f in photos)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(f.caption.isEmpty ? 'Photo du ${frDate(f.createdAt)}' : f.caption),
                subtitle: Text(f.visibleToClient ? 'Visible par le client' : 'Masquée au client'),
                value: f.visibleToClient,
                onChanged: _busy
                    ? null
                    : (v) => _guard(() => _api.setShared(f.id, v), v ? 'Photo de nouveau visible.' : 'Photo retirée de l\'espace client.'),
              ),
            const SectionHeader('Devis dans l\'espace client'),
            if (sentQuotes.isEmpty) Text('Aucun devis envoyé.', style: t.bodySmall),
            for (final q in sentQuotes)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(pdfFor.containsKey(q.id) ? Icons.picture_as_pdf : Icons.hourglass_bottom),
                title: Text(q.displayNumber),
                subtitle: Text(
                  pdfFor.containsKey(q.id)
                      ? 'Montant et PDF visibles par le client'
                      : q.serverVersion == null || q.dirty
                      ? 'Montant visible après synchronisation ; PDF publié ensuite'
                      : 'Montant visible ; PDF pas encore publié',
                ),
                trailing: pdfFor.containsKey(q.id) || q.number == null || q.dirty
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : () => _guard(() => sync.publishQuotePdf(p, q), 'PDF publié dans l\'espace client.'),
                        child: const Text('Publier'),
                      ),
              ),
          ],
        ],
      ),
    );
  }
}
