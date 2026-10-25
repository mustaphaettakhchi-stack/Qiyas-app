import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../domain/models.dart';
import '../../services/pdf_service.dart';
import '../../services/share_service.dart';
import '../widgets/common.dart';

/// E10 · Aperçu du PDF et partage.
class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key, required this.projectId, required this.quoteId});
  final String projectId;
  final String quoteId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    Quote? found;
    for (final x in p?.quotes ?? const <Quote>[]) {
      if (x.id == quoteId) found = x;
    }
    if (p == null || found == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Devis introuvable.')));
    }
    final q = found;
    final c = s.company;
    final message = quoteMessage(c, p, q);

    Future<void> sendPdf() async {
      final bytes = await PdfService.build(company: c, project: p, quote: q);
      final shared = await ShareService.sharePdf(bytes, '${q.number}.pdf', message);
      if (shared && q.status == QuoteStatus.draft) {
        s.markSent(p, q);
        if (context.mounted) showToast(context, 'Devis envoyé : il est maintenant figé.');
      }
    }

    Future<void> openWhatsApp() async {
      final ok = await ShareService.openWhatsApp(p.phone, message);
      if (!ok && context.mounted) {
        showToast(context, 'Numéro du client manquant ou WhatsApp indisponible.');
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(q.number), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: StatusPill(q.status))]),
      body: Column(children: [
        Expanded(
          child: PdfPreview(
            build: (_) => PdfService.build(company: c, project: p, quote: q),
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            pdfFileName: '${q.number}.pdf',
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              FilledButton.icon(
                onPressed: sendPdf,
                icon: const Icon(Icons.send),
                label: const Text('Envoyer le PDF (WhatsApp, e-mail…)'),
              ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: p.phone.isEmpty ? null : openWhatsApp,
                icon: const Icon(Icons.chat_outlined),
                label: const Text('Écrire au client sur WhatsApp'),
              ),
              const SizedBox(height: 6),
              if (q.status == QuoteStatus.draft)
                TextButton(onPressed: () => s.markSent(p, q), child: const Text('Marquer comme envoyé'))
              else
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: q.status == QuoteStatus.accepted
                          ? null
                          : () {
                              s.setStatus(p, q, QuoteStatus.accepted);
                              showToast(context, 'Bravo, chantier gagné.');
                            },
                      child: const Text('Accepté'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: q.status == QuoteStatus.refused
                          ? null
                          : () {
                              s.setStatus(p, q, QuoteStatus.refused);
                              showToast(context, 'Devis refusé. Créez une nouvelle version depuis l\'écran Devis.');
                            },
                      child: const Text('Refusé'),
                    ),
                  ),
                ]),
            ]),
          ),
        ),
      ]),
    );
  }
}
