import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/client_space.dart';
import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../widgets/common.dart';

/// Fil de messages d'un projet entre le client et l'équipe (USER_FLOWS P8).
///
/// Même écran des deux côtés : [asClient] choisit les routes du serveur. Les messages
/// ne sont pas conservés sur le téléphone ; une connexion est nécessaire.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.projectId, required this.title, required this.asClient});
  final String projectId;
  final String title;
  final bool asClient;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _text = TextEditingController();
  List<ProjectMessage>? _messages;
  String? _error;
  bool _sending = false;

  ClientSpaceApi get _api => ClientSpaceApi(context.read<SessionController>().api);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await _api.messages(widget.projectId, asClient: widget.asClient);
      if (mounted) {
        setState(() {
          _messages = m;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty || _sending) return;
    if (body.length > 2000) {
      showToast(context, 'Message trop long (2 000 caractères au maximum).');
      return;
    }
    setState(() => _sending = true);
    try {
      final m = await _api.postMessage(widget.projectId, body, asClient: widget.asClient);
      _text.clear();
      if (mounted) setState(() => _messages = [...?_messages, m]);
    } on ApiException catch (e) {
      // Le texte saisi est conservé pour pouvoir réessayer.
      if (mounted) showToast(context, e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final messages = _messages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [IconButton(tooltip: 'Actualiser', onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          Expanded(
            child: _error != null && messages == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: AlertBox(
                      _error!,
                      kind: AlertKind.error,
                      action: TextButton(onPressed: _load, child: const Text('Réessayer')),
                    ),
                  )
                : messages == null
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.asClient
                            ? 'Aucun message. Posez ici vos questions sur le projet : l\'équipe vous répondra.'
                            : 'Aucun message avec le client pour ce projet.',
                        textAlign: TextAlign.center,
                        style: t.bodyMedium,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        // « Mes » messages à droite : ceux du client côté client, ceux de l'équipe côté équipe.
                        final mine = m.fromClient == widget.asClient;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
                            child: Card(
                              color: mine ? cs.primaryContainer : cs.surfaceContainerHigh,
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(m.body, style: TextStyle(color: mine ? cs.onPrimaryContainer : cs.onSurface)),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${m.authorName}${m.fromClient ? '' : ' · Group LAMAALAM'} · ${frDateTime(m.createdAt)}',
                                      style: t.bodySmall?.copyWith(color: mine ? cs.onPrimaryContainer : cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(hintText: 'Votre message', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Envoyer',
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
