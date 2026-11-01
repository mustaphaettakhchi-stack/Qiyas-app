import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/format.dart';
import '../../../core/labels.dart';
import '../../../data/client_space.dart';
import '../../../session/api_client.dart';
import '../../../session/session_controller.dart';
import '../../widgets/common.dart';
import '../messages_screen.dart';

const kClientQuoteStatus = {
  'sent': 'En attente de votre réponse',
  'accepted': 'Accepté',
  'refused': 'Refusé',
  'superseded': 'Remplacé par une version plus récente',
};

const kClientSteps = {
  'project.create': 'Projet ouvert',
  'metre.validate': 'Métré validé',
  'estimate.send': 'Devis envoyé',
  'estimate.accept': 'Devis accepté',
  'estimate.refuse': 'Devis refusé',
};

/// Projet vu par le client : devis envoyés (montants et PDF), photos partagées,
/// étapes et messages. Jamais de déboursé, de marge ni de photo interne (A8.2).
class ClientProjectScreen extends StatefulWidget {
  const ClientProjectScreen({super.key, required this.projectId, required this.title});
  final String projectId;
  final String title;

  @override
  State<ClientProjectScreen> createState() => _ClientProjectScreenState();
}

class _ClientProjectScreenState extends State<ClientProjectScreen> {
  ClientProjectDetail? _detail;
  String? _error;

  ClientSpaceApi get _api => ClientSpaceApi(context.read<SessionController>().api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final d = await _api.project(widget.projectId);
      if (mounted) {
        setState(() {
          _detail = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openPdf(ClientQuote q) async {
    final api = _api;
    final name = '${q.reference ?? 'devis'}.pdf';
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(q.reference ?? 'Devis')),
          body: PdfPreview(
            build: (_) => api.fileBytes(q.pdfFileId!),
            pdfFileName: name,
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            onError: (_, e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AlertBox(e is ApiException ? e.message : 'Impossible d\'afficher le devis.', kind: AlertKind.error),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final d = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.project.title ?? widget.title, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Actualiser', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: d == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => MessagesScreen(projectId: widget.projectId, title: 'Messages · ${d.project.title}', asClient: true),
                  ),
                );
                await _load(); // le fil vient d'être lu : compteur à jour
              },
              icon: Badge(
                isLabelVisible: d.project.unreadMessages > 0,
                label: Text('${d.project.unreadMessages}'),
                child: const Icon(Icons.chat_bubble_outline),
              ),
              label: Text(d.project.unreadMessages > 0 ? 'Messages · ${d.project.unreadMessages} non lu(s)' : 'Messages'),
            ),
      body: _error != null && d == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: AlertBox(
                _error!,
                kind: AlertKind.error,
                action: TextButton(onPressed: _load, child: const Text('Réessayer')),
              ),
            )
          : d == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  Text(
                    [
                      if (d.project.reference.isNotEmpty) d.project.reference,
                      kProjectStatuses[d.project.status] ?? d.project.status,
                    ].join(' · '),
                    style: t.labelLarge,
                  ),
                  if ([d.project.address, d.project.city].any((x) => x.isNotEmpty))
                    Text([d.project.address, d.project.city].where((x) => x.isNotEmpty).join(', '), style: t.bodySmall),
                  const SectionHeader('Devis'),
                  if (d.quotes.isEmpty) Text('Aucun devis envoyé pour l\'instant.', style: t.bodySmall),
                  for (final q in d.quotes)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.request_quote_outlined),
                        title: Text('${q.reference ?? 'Devis'} · ${money(q.totalTtcCents, q.currency)} TTC'),
                        subtitle: Text(
                          [
                            kClientQuoteStatus[q.status] ?? q.status,
                            'du ${frDate(q.issueDate)}',
                            'valable jusqu\'au ${frDate(q.issueDate.add(Duration(days: q.validityDays)))}',
                            if (q.pdfFileId == null) 'document en préparation',
                          ].join(' · '),
                        ),
                        trailing: q.pdfFileId == null ? null : const Icon(Icons.picture_as_pdf_outlined),
                        onTap: q.pdfFileId == null ? null : () => _openPdf(q),
                      ),
                    ),
                  if (d.quotes.any((q) => q.status == 'sent'))
                    Text(
                      'Pour accepter un devis, retournez-le daté et signé à Group LAMAALAM '
                      '(aucune signature électronique dans l\'application).',
                      style: t.bodySmall,
                    ),
                  const SectionHeader('Photos partagées'),
                  if (d.photos.isEmpty) Text('Aucune photo partagée pour l\'instant.', style: t.bodySmall),
                  if (d.photos.isNotEmpty)
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 6,
                      crossAxisSpacing: 6,
                      children: [for (final p in d.photos) _RemotePhoto(photo: p, api: _api)],
                    ),
                  const SectionHeader('Étapes'),
                  if (d.timeline.isEmpty) Text('Aucune étape enregistrée.', style: t.bodySmall),
                  for (final s in d.timeline)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text([kClientSteps[s.action] ?? s.action, if (s.reference != null) s.reference!].join(' · ')),
                      subtitle: Text(frDate(s.at)),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Vignette chargée par lien signé ; un toucher l'affiche en grand.
class _RemotePhoto extends StatefulWidget {
  const _RemotePhoto({required this.photo, required this.api});
  final SharedPhoto photo;
  final ClientSpaceApi api;

  @override
  State<_RemotePhoto> createState() => _RemotePhotoState();
}

class _RemotePhotoState extends State<_RemotePhoto> {
  late Future<Uint8List> _bytes = widget.api.fileBytes(widget.photo.id);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snap) {
      final cs = Theme.of(context).colorScheme;
      if (snap.hasError) {
        return InkWell(
          onTap: () => setState(() => _bytes = widget.api.fileBytes(widget.photo.id)),
          child: Container(
            color: cs.surfaceContainerHigh,
            child: const Center(child: Icon(Icons.refresh, semanticLabel: 'Photo indisponible, toucher pour réessayer')),
          ),
        );
      }
      if (!snap.hasData) return Container(color: cs.surfaceContainerHigh);
      final bytes = snap.data!;
      return Semantics(
        label: widget.photo.caption.isEmpty ? 'Photo du chantier' : widget.photo.caption,
        button: true,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                appBar: AppBar(title: Text(widget.photo.caption.isEmpty ? frDate(widget.photo.createdAt) : widget.photo.caption)),
                body: InteractiveViewer(child: Center(child: Image.memory(bytes))),
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
      );
    },
  );
}
