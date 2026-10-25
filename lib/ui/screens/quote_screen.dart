import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';
import 'preview_screen.dart';
import 'profile_screen.dart';

/// E9 · Édition du devis.
class QuoteScreen extends StatelessWidget {
  const QuoteScreen({super.key, required this.projectId, required this.quoteId});
  final String projectId;
  final String quoteId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    Quote? q;
    for (final x in p?.quotes ?? const <Quote>[]) {
      if (x.id == quoteId) q = x;
    }
    if (p == null || q == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Devis introuvable.')));
    }
    final quote = q;
    final c = s.company;
    final m = projectMeasures(p);
    final totals = quoteTotals(p, quote, c.vatPercent);
    final locked = quote.locked;
    final t = Theme.of(context).textTheme;
    void edit(VoidCallback f) => s.mutate(f, touch: p);

    Future<void> addLine() async {
      final choice = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Ajouter une prestation')),
              for (final x in s.prestations.where((x) => x.active))
                ListTile(
                  title: Text(x.name),
                  subtitle: Text('${dh(x.unitPriceCents)} / ${x.unit} · ${kBaseLabel[x.base]}'),
                  onTap: () => Navigator.pop(ctx, x),
                ),
              ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('Ligne libre'),
                onTap: () => Navigator.pop(ctx, 'free'),
              ),
            ]),
          ),
        ),
      );
      if (choice is Prestation) {
        s.addLineFromPrestation(p, quote, choice);
      } else if (choice == 'free') {
        s.addFreeLine(p, quote);
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(quote.number), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('${frDate(quote.date)} · ${p.client.isEmpty ? 'Client à renseigner' : p.client}', style: t.bodyMedium)),
          StatusPill(quote.status),
        ]),
        const SizedBox(height: 8),
        if (locked)
          AlertBox(
            'Ce devis est envoyé : il ne peut plus être modifié.',
            action: FilledButton.tonal(
              onPressed: () {
                final n = s.newVersion(p, quote);
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuoteScreen(projectId: p.id, quoteId: n.id)));
              },
              child: Text('Créer la version ${quote.version + 1}'),
            ),
          ),
        if (quote.lines.isEmpty) const AlertBox('Ajoutez une prestation : la quantité est reprise du métré.'),
        for (var i = 0; i < quote.lines.length; i++)
          _LineCard(
            key: ValueKey(quote.lines[i].id),
            project: p,
            quote: quote,
            index: i,
            measures: m,
            locked: locked,
            onEdit: edit,
          ),
        if (!locked)
          OutlinedButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Ajouter une prestation')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: NumField(
              label: 'Remise',
              suffix: '%',
              value: quote.discountPercent,
              enabled: !locked,
              onChanged: (v) => edit(() => quote.discountPercent = v.clamp(0, 100).toDouble()),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: NumField(
              label: 'Acompte demandé',
              suffix: '%',
              value: quote.depositPercent,
              enabled: !locked,
              onChanged: (v) => edit(() => quote.depositPercent = v.clamp(0, 100).toDouble()),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _Totals(totals: totals, vat: c.vatPercent),
        const SizedBox(height: 12),
        if (!c.hasValidIce)
          AlertBox(
            'Renseignez l\'ICE de votre entreprise (15 chiffres) pour générer le devis.',
            kind: AlertKind.error,
            action: FilledButton.tonal(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: const Text('Ouvrir le profil'),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: c.hasValidIce && quote.lines.isNotEmpty
              ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => PreviewScreen(projectId: p.id, quoteId: quote.id)))
              : null,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: const Text('Générer le PDF'),
        ),
        if (p.quotes.length > 1) ...[
          const SectionHeader('Autres versions'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in p.quotes.where((o) => o.id != quote.id))
              ActionChip(
                label: Text('${o.number} · ${kStatusLabel[o.status]}'),
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuoteScreen(projectId: p.id, quoteId: o.id))),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.project,
    required this.quote,
    required this.index,
    required this.measures,
    required this.locked,
    required this.onEdit,
  });

  final Project project;
  final Quote quote;
  final int index;
  final Measures measures;
  final bool locked;
  final void Function(VoidCallback) onEdit;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final l = quote.lines[index];
    final qty = lineQuantity(project, l, measures: measures);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: l.prestationId == null && !locked
                  ? EditField(label: 'Désignation', value: l.label, onChanged: (v) => onEdit(() => l.label = v))
                  : Text(l.label, style: t.titleSmall),
            ),
            if (!locked) ...[
              IconButton(tooltip: 'Monter', onPressed: index > 0 ? () => s.moveLine(project, quote, index, -1) : null, icon: const Icon(Icons.arrow_upward)),
              IconButton(
                tooltip: 'Descendre',
                onPressed: index < quote.lines.length - 1 ? () => s.moveLine(project, quote, index, 1) : null,
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(tooltip: 'Supprimer la ligne', onPressed: () => onEdit(() => quote.lines.removeAt(index)), icon: const Icon(Icons.close)),
            ],
          ]),
          if (l.description.isNotEmpty) Text(l.description, style: t.bodySmall),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: NumField(
                label: 'Quantité (${l.unit})',
                value: qty,
                enabled: !locked,
                onChanged: (v) => onEdit(() {
                  l.quantity = v;
                  l.manual = true;
                }),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: NumField(
                label: 'P.U. HT',
                suffix: 'DH',
                value: l.unitPriceCents / 100,
                enabled: !locked,
                onChanged: (v) => onEdit(() => l.unitPriceCents = (v * 100).round()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  dh(lineTotalCents(project, l, measures: measures)),
                  textAlign: TextAlign.right,
                  style: t.titleSmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ),
          ]),
          if (l.base != QuantityBase.free && l.frozenQuantity == null)
            l.manual
                ? Row(children: [
                    Expanded(
                      child: Text('Quantité saisie à la main : elle ne suit plus le métré.',
                          style: t.bodySmall?.copyWith(color: cs.tertiary, fontWeight: FontWeight.w600)),
                    ),
                    if (!locked) TextButton(onPressed: () => onEdit(() => l.manual = false), child: const Text('Reprendre le métré')),
                  ])
                : Text('Quantité reprise du métré : ${kBaseLabel[l.base]}', style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.vat});
  final QuoteTotals totals;
  final double vat;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(String a, String b, {bool big = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: big ? t.titleLarge?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium)),
            Text(b, style: (big ? t.titleLarge?.copyWith(fontWeight: FontWeight.w800) : t.bodyMedium)?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          if (totals.discount > 0) ...[
            row('Sous-total HT', dh(totals.subtotal)),
            row('Remise', '- ${dh(totals.discount)}'),
          ],
          row('Total HT', dh(totals.ht)),
          row('TVA ${fmt2(vat)} %', dh(totals.vat)),
          const Divider(),
          row('Total TTC', dh(totals.ttc), big: true),
          row('Acompte', dh(totals.deposit)),
        ]),
      ),
    );
  }
}
