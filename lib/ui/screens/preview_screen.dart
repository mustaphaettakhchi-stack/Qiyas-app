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
    final client = s.clientOf(p);
    final phone = client?.phone ?? '';
    final message = quoteMessage(c, p, q, client: client);

    // Seul un devis validé et numéroté par le serveur peut partir chez le client.
    final canSend = q.status != QuoteStatus.draft && q.status != QuoteStatus.superseded && (q.number != null || q.legacy);
    final fileName = '${q.displayNumber.replaceAll(' ', '_')}.pdf';

    Future<void> sendPdf() async {
      final bytes = await PdfService.build(company: c, project: p, quote: q, client: client);
      final shared = await ShareService.sharePdf(bytes, fileName, message);
      if (shared && q.status == QuoteStatus.validated) {
        s.markSent(p, q);
        if (context.mounted) showToast(context, 'Devis marqué comme envoyé.');
      }
    }

    Future<void> openWhatsApp() async {
      final ok = await ShareService.openWhatsApp(phone, message);
      if (!ok && context.mounted) {
        showToast(context, 'Numéro du client manquant ou WhatsApp indisponible.');
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(q.displayNumber), actions: [Padding(padding: const EdgeInsets.only(right: 12), child: StatusPill(q.status))]),
      body: Column(children: [
        Expanded(
          child: PdfPreview(
            build: (_) => PdfService.build(company: c, project: p, quote: q, client: client),
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: false,
            allowSharing: false,
            pdfFileName: fileName,
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!canSend)
                AlertBox(
                  q.status == QuoteStatus.draft
                      ? 'Aperçu d\'un brouillon (filigrane) : validez le devis pour pouvoir l\'envoyer.'
                      : q.status == QuoteStatus.superseded
                          ? 'Version remplacée : elle ne peut plus être envoyée.'
                          : 'Le numéro du devis n\'est pas encore attribué : synchronisez avant l\'envoi.',
                  kind: AlertKind.warning,
                )
              else ...[
                FilledButton.icon(
                  onPressed: sendPdf,
                  icon: const Icon(Icons.send),
                  label: const Text('Envoyer le PDF (WhatsApp, e-mail…)'),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: phone.isEmpty ? null : openWhatsApp,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Écrire au client sur WhatsApp'),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
