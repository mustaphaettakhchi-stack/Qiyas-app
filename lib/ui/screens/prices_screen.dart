import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../data/sample_data.dart';
import '../../domain/models.dart';
import '../widgets/common.dart';

/// E8 · Grille de prix de l'entreprise.
class PricesScreen extends StatelessWidget {
  const PricesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grille de prix'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Ajouter une grille modèle',
            icon: const Icon(Icons.library_add_outlined),
            onSelected: (trade) {
              s.addTemplate(trade);
              showToast(context, 'Grille « $trade » ajoutée : complétez les prix.');
            },
            itemBuilder: (_) => [
              for (final trade in kPriceTemplates.keys) PopupMenuItem(value: trade, child: Text(trade)),
            ],
          ),
          const SyncBadge(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          s.addPrestation();
          showToast(context, 'Prestation ajoutée en bas de la liste.');
        },
        icon: const Icon(Icons.add),
        label: const Text('Prestation'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Text(
          'Vos prestations et prix unitaires HT. Dans un devis, la quantité vient de la base choisie.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        for (final x in s.prestations) _PrestationCard(key: ValueKey(x.id), x: x),
      ]),
    );
  }
}

class _PrestationCard extends StatelessWidget {
  const _PrestationCard({super.key, required this.x});
  final Prestation x;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    void edit(VoidCallback f) => s.mutate(f);
    return Opacity(
      opacity: x.active ? 1 : 0.55,
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              Expanded(flex: 3, child: EditField(label: 'Prestation', value: x.name, onChanged: (v) => edit(() => x.name = v))),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: NumField(
                  label: 'Prix HT',
                  suffix: 'DH',
                  value: x.unitPriceCents / 100,
                  onChanged: (v) => edit(() => x.unitPriceCents = (v * 100).round()),
                ),
              ),
            ]),
            EditField(label: 'Description (facultatif)', value: x.description, onChanged: (v) => edit(() => x.description = v)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: kUnits.contains(x.unit) ? x.unit : kUnits.first,
                  items: [for (final u in kUnits) DropdownMenuItem(value: u, child: Text('Unité : $u'))],
                  onChanged: (u) => edit(() => x.unit = u ?? x.unit),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<QuantityBase>(
                  isExpanded: true,
                  value: x.base,
                  items: [for (final b in QuantityBase.values) DropdownMenuItem(value: b, child: Text(kBaseLabel[b]!))],
                  onChanged: (b) => edit(() => x.base = b ?? x.base),
                ),
              ),
            ]),
            Row(children: [
              TextButton(onPressed: () => s.duplicatePrestation(x), child: const Text('Dupliquer')),
              const Spacer(),
              const Text('Active'),
              Switch(value: x.active, onChanged: (v) => edit(() => x.active = v)),
            ]),
          ]),
        ),
      ),
    );
  }
}
