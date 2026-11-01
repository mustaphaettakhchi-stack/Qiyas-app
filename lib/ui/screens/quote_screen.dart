import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/metre.dart';
import '../../domain/models.dart';
import '../../session/session_controller.dart';
import '../../sync/sync_engine.dart';
import '../widgets/common.dart';
import 'library_screen.dart';
import 'metre_screen.dart';
import 'preview_screen.dart';

/// Taux de TVA proposés (en points de base). Le taux par défaut vient du profil de l'entreprise ;
/// les taux applicables aux travaux sont à confirmer par l'expert-comptable.
const kVatRates = [0, 700, 1000, 1400, 2000];

/// Édition d'une version de devis et de son cycle de vie.
class QuoteScreen extends StatelessWidget {
  const QuoteScreen({super.key, required this.projectId, required this.quoteId});
  final String projectId;
  final String quoteId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    final p = s.project(projectId);
    final q = p?.quotes.where((x) => x.id == quoteId).firstOrNull;
    if (p == null || q == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Devis introuvable.')));
    }
    final m = projectMeasures(p);
    final totals = quoteTotals(p, q);
    final locked = q.locked;
    final t = Theme.of(context).textTheme;
    final isAdmin = (session.user?.isAdmin ?? false) || session.isDemo;
    void edit(VoidCallback f) => s.editQuote(p, q, f);
    void open(Widget w) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => w));
    void replace(Quote other) =>
        Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => QuoteScreen(projectId: p.id, quoteId: other.id)));
    final hasCostPlus = q.lines.any((l) => l.pricing == 'cost_plus');

    Future<void> addLine() async {
      final choice = await showModalBottomSheet<Object>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Ajouter un ouvrage de la bibliothèque')),
              for (final x in s.workItems.where((x) => x.active))
                ListTile(
                  title: Text([if (x.code.isNotEmpty) x.code, x.name].join(' · ')),
                  subtitle: Text([
                    priceText(x.salePriceCents, x.currency, x.unitLabel),
                    baseLabel(x.base, x.countKey),
                    if (x.wasteRateBp > 0) 'perte ${pct(x.wasteRateBp)}',
                  ].join(' · ')),
                  onTap: () => Navigator.pop(ctx, x),
                ),
              ListTile(leading: const Icon(Icons.edit_note), title: const Text('Ligne libre'), onTap: () => Navigator.pop(ctx, 'free')),
            ]),
          ),
        ),
      );
      if (choice is WorkItem) {
        s.addLineFromWorkItem(p, q, choice);
      } else if (choice == 'free') {
        s.addFreeLine(p, q);
      }
    }

    Future<void> validate() async {
      final problems = s.validationProblems(p, q, isAdmin: isAdmin);
      if (problems.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Validation impossible'),
            content: Text(problems.map((x) => '• $x').join('\n')),
            actions: [
              if (problems.any((x) => x.contains('métré')))
                TextButton(
                  onPressed: () {
                    Navigator.pop(c);
                    open(MetreScreen(projectId: p.id));
                  },
                  child: const Text('Ouvrir le métré'),
                ),
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Compris')),
            ],
          ),
        );
        return;
      }
      if (!await confirm(
        context,
        'Valider ce devis ?',
        'Les quantités et les prix seront figés. Toute modification ultérieure créera une nouvelle version. '
            'Le numéro du devis sera attribué par le serveur à la prochaine synchronisation.',
        ok: 'Valider',
      )) {
        return;
      }
      s.validateQuote(p, q, userId: session.user?.id ?? '');
      if (context.mounted) await context.read<SyncEngine>().syncNow();
    }

    Future<void> decision() async {
      final note = TextEditingController();
      final accepted = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Réponse du client'),
          content: TextField(controller: note, maxLines: 3, decoration: const InputDecoration(labelText: 'Commentaire (moyen, date de l\'accord…)')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
            OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Refusé')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Accepté')),
          ],
        ),
      );
      if (accepted != null) s.decide(p, q, accepted: accepted, note: note.text);
      note.dispose();
    }

    final versions = p.quotes.where((x) => x.estimateId == q.estimateId && x.id != q.id).toList();

    return Scaffold(
      appBar: AppBar(title: Text(q.displayNumber), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (q.syncError != null) AlertBox('Envoi refusé : ${q.syncError}', kind: AlertKind.error),
        Row(children: [
          Expanded(child: Text('${frDate(q.date)} · ${s.clientName(p)}', style: t.bodyMedium)),
          StatusPill(q.status),
        ]),
        const SizedBox(height: 8),
        ..._statusNotice(context, s, p, q, isAdmin, replace),
        if (!locked) ...[
          EditField(key: ValueKey('title-${q.id}'), label: 'Objet du devis', value: q.title, onChanged: (v) => edit(() => q.title = v)),
          _CurrencyRow(project: p, quote: q),
        ],
        const SizedBox(height: 8),
        if (q.lines.isEmpty) const AlertBox('Ajoutez un ouvrage : sa quantité est reprise du métré.'),
        for (var i = 0; i < q.lines.length; i++)
          _LineCard(key: ValueKey(q.lines[i].id), project: p, quote: q, index: i, measures: m, locked: locked, onEdit: edit),
        if (!locked)
          OutlinedButton.icon(onPressed: addLine, icon: const Icon(Icons.add), label: const Text('Ajouter une ligne')),
        const SizedBox(height: 12),
        if (!locked)
          Wrap(spacing: 12, runSpacing: 8, children: [
            _BpField(label: 'Remise', value: q.discountBp, onChanged: (v) => edit(() => q.discountBp = v.clamp(0, 10000))),
            _BpField(label: 'Acompte', value: q.depositBp, onChanged: (v) => edit(() => q.depositBp = v.clamp(0, 10000))),
            NumFieldBox(
              child: NumField(
                label: 'Validité',
                suffix: 'jours',
                decimals: 0,
                value: q.validityDays.toDouble(),
                onChanged: (v) => edit(() => q.validityDays = v.round().clamp(1, 365)),
              ),
            ),
            if (hasCostPlus) ...[
              _BpField(label: 'Frais indirects', value: q.overheadBp, onChanged: (v) => edit(() => q.overheadBp = v.clamp(0, 100000))),
              _BpField(label: 'Marge', value: q.marginBp, onChanged: (v) => edit(() => q.marginBp = v.clamp(0, 100000))),
            ],
          ]),
        if (hasCostPlus && !locked)
          Text('Frais et marge s\'appliquent aux lignes à prix calculé et n\'apparaissent pas sur le PDF du client.', style: t.bodySmall),
        const SizedBox(height: 12),
        _Totals(totals: totals, quote: q),
        const SizedBox(height: 12),
        if (q.status == QuoteStatus.draft) ...[
          FilledButton.icon(onPressed: validate, icon: const Icon(Icons.verified_outlined), label: const Text('Valider le devis')),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: q.lines.isEmpty ? null : () => open(PreviewScreen(projectId: p.id, quoteId: q.id)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Aperçu du PDF (brouillon)'),
          ),
          if (q.serverVersion == null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Supprimer ce brouillon ?', 'Il n\'a jamais été envoyé au serveur.', ok: 'Supprimer')) {
                  s.deleteLocalDraft(p, q);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Supprimer ce brouillon'),
            ),
        ] else ...[
          FilledButton.icon(
            onPressed: q.number == null && !q.legacy ? null : () => open(PreviewScreen(projectId: p.id, quoteId: q.id)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(q.status == QuoteStatus.validated ? 'Envoyer au client' : 'Voir le PDF'),
          ),
          if (q.status == QuoteStatus.sent && !q.legacy)
            OutlinedButton.icon(onPressed: decision, icon: const Icon(Icons.how_to_reg_outlined), label: const Text('Réponse du client')),
          if (q.status == QuoteStatus.validated || q.status == QuoteStatus.sent || q.legacy)
            TextButton(onPressed: () => replace(s.newVersion(p, q)), child: const Text('Modifier : créer une nouvelle version')),
        ],
        if (versions.isNotEmpty) ...[
          const SectionHeader('Autres versions'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in versions)
              ActionChip(label: Text('${o.displayNumber} · ${kStatusLabel[o.status]}'), onPressed: () => replace(o)),
          ]),
        ],
      ]),
    );
  }

  List<Widget> _statusNotice(BuildContext context, AppState s, Project p, Quote q, bool isAdmin, void Function(Quote) replace) {
    final state = metreState(p);
    return [
      if (q.legacy)
        const AlertBox('Devis de l\'ancienne version Qiyas : conservé sur ce téléphone, non synchronisé. '
            'Pour le modifier, créez une nouvelle version.'),
      if (q.status == QuoteStatus.draft && state != MetreState.validated)
        AlertBox(
          state == MetreState.stale
              ? 'Le métré a changé depuis sa validation : revalidez-le avant de valider ce devis.'
              : 'Métré non validé : validez-le avant de valider ce devis.',
          kind: AlertKind.warning,
        ),
      if (q.status == QuoteStatus.draft && !isAdmin)
        const AlertBox('Vous préparez ce devis ; sa validation est faite par un administrateur.'),
      if (q.status == QuoteStatus.validated && q.number == null)
        const AlertBox('Devis validé. Son numéro sera attribué par le serveur à la prochaine synchronisation ; '
            'il pourra ensuite être envoyé au client.', kind: AlertKind.warning),
      if (q.status == QuoteStatus.accepted || q.status == QuoteStatus.refused)
        AlertBox('${q.status == QuoteStatus.accepted ? 'Accepté' : 'Refusé'} le ${frDate(q.decidedAt ?? q.date)}'
            '${q.decisionNote.isEmpty ? '' : ' : ${q.decisionNote}'}'),
      if (q.status == QuoteStatus.superseded) const AlertBox('Version remplacée par une version plus récente.'),
      const SizedBox(height: 4),
    ];
  }
}

/// Conteneur de largeur fixe pour les petits champs numériques.
class NumFieldBox extends StatelessWidget {
  const NumFieldBox({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: 150, child: child);
}

class _BpField extends StatelessWidget {
  const _BpField({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => NumFieldBox(
        child: NumField(label: label, suffix: '%', value: value / 100, onChanged: (v) => onChanged((v * 100).round())),
      );
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({required this.project, required this.quote});
  final Project project;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final q = quote;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'MAD', label: Text('Dirhams (MAD)')), ButtonSegment(value: 'EUR', label: Text('Euros (€)'))],
          selected: {q.currency},
          onSelectionChanged: (v) => s.setCurrency(project, q, v.first,
              rateE4: q.exchangeRateE4, rateDate: q.exchangeRateDate ?? DateTime.now(), rateSource: q.exchangeRateSource),
        ),
        if (q.currency == 'EUR') ...[
          Row(children: [
            Expanded(
              child: NumField(
                key: ValueKey('rate-${q.id}'),
                label: 'Taux : MAD pour 1 €',
                decimals: 4,
                value: (q.exchangeRateE4 ?? 0) / 10000,
                onChanged: (v) => s.setCurrency(project, q, 'EUR',
                    rateE4: v <= 0 ? null : (v * 10000).round(), rateDate: q.exchangeRateDate, rateSource: q.exchangeRateSource),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final d = await showDatePicker(context: context, initialDate: q.exchangeRateDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) s.editQuote(project, q, () => q.exchangeRateDate = d);
              },
              child: Text(q.exchangeRateDate == null ? 'Date du taux' : frDate(q.exchangeRateDate!)),
            ),
          ]),
          EditField(
            key: ValueKey('rs-${q.id}'),
            label: 'Source du taux (ex. Bank Al-Maghrib)',
            value: q.exchangeRateSource,
            onChanged: (v) => s.editQuote(project, q, () => q.exchangeRateSource = v),
          ),
          Text('Les prix de la bibliothèque en MAD sont convertis à ce taux. Vérifiez les lignes libres.',
              style: Theme.of(context).textTheme.bodySmall),
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
    final price = lineUnitPriceCents(quote, l);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final cur = quote.currency;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: l.workItemId == null && !locked
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
          if (!locked)
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'direct', label: Text('Prix de vente')),
                ButtonSegment(value: 'cost_plus', label: Text('Prix calculé')),
              ],
              selected: {l.pricing},
              onSelectionChanged: (v) => onEdit(() => l.pricing = v.first),
            ),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.end, children: [
            NumFieldBox(
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
            if (l.pricing == 'direct')
              NumFieldBox(
                child: MoneyField(
                  key: ValueKey('pu-${l.id}-${quote.currency}'),
                  label: 'Prix unitaire HT',
                  suffix: cur == 'EUR' ? '€' : 'MAD',
                  cents: l.priceMissing ? null : l.unitPriceCents,
                  enabled: !locked,
                  onChanged: (v) => onEdit(() {
                    l.priceMissing = v == null;
                    l.unitPriceCents = v ?? 0;
                    l.sourcePriceCents = null; // prix saisi : plus de conversion automatique
                  }),
                ),
              )
            else ...[
              NumFieldBox(
                child: MoneyField(
                  key: ValueKey('mat-${l.id}'),
                  label: 'Fournitures / u',
                  cents: l.materialCostCents,
                  enabled: !locked,
                  onChanged: (v) => onEdit(() => l.materialCostCents = v),
                ),
              ),
              NumFieldBox(
                child: MoneyField(
                  key: ValueKey('lab-${l.id}'),
                  label: 'Main-d\'œuvre / u',
                  cents: l.labourCostCents,
                  enabled: !locked,
                  onChanged: (v) => onEdit(() => l.labourCostCents = v),
                ),
              ),
            ],
            DropdownButton<int>(
              value: kVatRates.contains(l.vatRateBp) ? l.vatRateBp : null,
              hint: Text('TVA ${pctBp(l.vatRateBp)}'),
              items: [for (final r in kVatRates) DropdownMenuItem(value: r, child: Text('TVA ${pctBp(r)}'))],
              onChanged: locked ? null : (v) => onEdit(() => l.vatRateBp = v ?? l.vatRateBp),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(
                l.pricing == 'cost_plus' && price != null ? 'Prix calculé : ${money(price, cur)} / ${l.unit}' : '',
                style: t.bodySmall,
              ),
            ),
            Text(price == null ? 'Prix à renseigner' : money(lineTotalCents(project, quote, l, measures: measures), cur),
                style: t.titleSmall?.copyWith(color: price == null ? cs.primary : null, fontFeatures: const [FontFeature.tabularFigures()])),
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
                : Text(_trace(project, l, measures), style: t.bodySmall),
        ]),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.quote});
  final QuoteTotals totals;
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String m(int c) => money(c, quote.currency);
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: strong ? t.titleMedium : null)),
            Text(value, style: (strong ? t.titleMedium : t.bodyMedium)?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          if (totals.discount > 0) ...[
            row('Sous-total HT', m(totals.subtotal)),
            row('Remise ${pctBp(quote.discountBp)}', '- ${m(totals.discount)}'),
          ],
          row('Total HT', m(totals.ht)),
          for (final e in (totals.vatByRate.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
            row('TVA ${pctBp(e.key)}', m(e.value)),
          const Divider(),
          row('Total TTC', m(totals.ttc), strong: true),
          if (quote.depositBp > 0) row('Acompte (${pctBp(quote.depositBp)})', m(totals.deposit)),
        ]),
      ),
    );
  }
}

/// Explication de la quantité d'une ligne : base, quantité nette, perte, quantité retenue.
String _trace(Project p, QuoteLine l, Measures m) {
  final net = lineNetQuantity(p, l, measures: m) ?? 0;
  final base = l.base == QuantityBase.count ? kCountItems[l.countKey]?.$2 ?? 'élément compté' : kBaseLabel[l.base]!;
  if (l.wasteRateBp == 0) return 'Quantité reprise du métré : $base = ${fmt2(net)} ${l.unit}.';
  return 'Métré : $base = ${fmt2(net)} ${l.unit} + perte ${pct(l.wasteRateBp)} '
      '= ${fmt2(lineQuantity(p, l, measures: m))} ${l.unit}.';
}
