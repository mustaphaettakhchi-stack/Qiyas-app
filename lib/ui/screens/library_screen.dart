import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/messages.dart';
import '../../data/app_state.dart';
import '../../data/templates.dart';
import '../../domain/models.dart';
import '../../session/api_client.dart';
import '../../session/session_controller.dart';
import '../../sync/sync_engine.dart';
import '../widgets/common.dart';

/// Droit de modifier la bibliothèque : administrateur, ou version de démonstration sans serveur.
bool canEditLibrary(BuildContext context) {
  final s = context.watch<SessionController>();
  return (s.user?.isAdmin ?? false) || s.isDemo;
}

String priceText(int? cents, String currency, String unitLabel) =>
    cents == null ? 'Prix à renseigner' : '${currency == 'EUR' ? eur(cents) : dh(cents)} / $unitLabel';

String eur(int cents) => '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

String pct(int bp) => '${(bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 1).replaceAll('.', ',')} %';

enum _Tab { workItems, materials, suppliers }

/// Bibliothèque : ouvrages, matériaux, fournisseurs. Démarre vide en production.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  _Tab _tab = _Tab.workItems;
  String _query = '';
  String? _category;

  bool _match(String text) => _query.trim().length < 2 || text.toLowerCase().contains(_query.trim().toLowerCase());

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final editable = canEditLibrary(context);
    final isAdmin = context.watch<SessionController>().user?.isAdmin ?? false;

    final List<Widget> items = switch (_tab) {
      _Tab.workItems => [
          for (final w in s.workItems)
            if ((_category == null || w.category == _category) && _match('${w.code} ${w.name} ${w.description}'))
              Card(
                child: ListTile(
                  title: Text([if (w.code.isNotEmpty) w.code, w.name].join(' · ')),
                  subtitle: Text([
                    kCategories[w.category] ?? w.category,
                    baseLabel(w.base, w.countKey),
                    if (w.wasteRateBp > 0) 'perte ${pct(w.wasteRateBp)}',
                    if (!w.active) 'inactif',
                    if (w.serverVersion == null && !editable) 'sur ce téléphone uniquement',
                  ].join(' · ')),
                  trailing: Text(priceText(w.salePriceCents, w.currency, w.unitLabel),
                      style: TextStyle(color: w.salePriceCents == null ? Theme.of(context).colorScheme.primary : null)),
                  onTap: () => _open(WorkItemScreen(id: w.id)),
                ),
              ),
        ],
      _Tab.materials => [
          for (final m in s.materials)
            if ((_category == null || m.category == _category) && _match('${m.name} ${m.brand} ${m.reference}'))
              Card(
                child: ListTile(
                  title: Text(m.name),
                  subtitle: Text([
                    kCategories[m.category] ?? m.category,
                    if (m.brand.isNotEmpty) m.brand,
                    if (s.supplier(m.supplierId) != null) s.supplier(m.supplierId)!.name,
                  ].join(' · ')),
                  trailing: Text(priceText(m.salePriceCents, m.currency, m.unitLabel)),
                  onTap: () => _open(MaterialScreen(id: m.id)),
                ),
              ),
        ],
      _Tab.suppliers => [
          for (final x in s.suppliers)
            if (_match('${x.name} ${x.city} ${x.contactName}'))
              Card(
                child: ListTile(
                  title: Text(x.name),
                  subtitle: Text([x.city, x.phone].where((t) => t.isNotEmpty).join(' · ')),
                  onTap: () => _open(SupplierScreen(id: x.id)),
                ),
              ),
        ],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bibliothèque'),
        actions: [
          if (editable)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'import') {
                  _open(const ImportScreen());
                } else {
                  s.addTemplate(v);
                  showToast(context, 'Ouvrages « $v » ajoutés, sans prix : complétez-les.');
                }
              },
              itemBuilder: (_) => [
                if (isAdmin) const PopupMenuItem(value: 'import', child: Text('Importer un fichier CSV')),
                for (final t in kPriceTemplates.keys) PopupMenuItem(value: t, child: Text('Modèles : $t')),
              ],
            ),
          const SyncBadge(),
        ],
      ),
      floatingActionButton: editable
          ? FloatingActionButton.extended(
              onPressed: () => switch (_tab) {
                _Tab.workItems => _open(WorkItemScreen(id: s.addWorkItem().id)),
                _Tab.materials => _open(MaterialScreen(id: s.addMaterial().id)),
                _Tab.suppliers => _open(SupplierScreen(id: s.addSupplier().id)),
              },
              icon: const Icon(Icons.add),
              label: Text(switch (_tab) {
                _Tab.workItems => 'Ouvrage',
                _Tab.materials => 'Matériau',
                _Tab.suppliers => 'Fournisseur',
              }),
            )
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        SegmentedButton<_Tab>(
          segments: const [
            ButtonSegment(value: _Tab.workItems, label: Text('Ouvrages')),
            ButtonSegment(value: _Tab.materials, label: Text('Matériaux')),
            ButtonSegment(value: _Tab.suppliers, label: Text('Fournisseurs')),
          ],
          selected: {_tab},
          onSelectionChanged: (v) => setState(() {
            _tab = v.first;
            _category = null;
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Rechercher'),
          onChanged: (v) => setState(() => _query = v),
        ),
        if (_tab != _Tab.suppliers) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(label: const Text('Toutes'), selected: _category == null, onSelected: (_) => setState(() => _category = null)),
            for (final e in kCategories.entries)
              ChoiceChip(label: Text(e.value), selected: _category == e.key, onSelected: (_) => setState(() => _category = e.key)),
          ]),
        ],
        const SizedBox(height: 8),
        if (!editable)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: AlertBox('Bibliothèque gérée par l\'administrateur : consultation seule.'),
          ),
        if (items.isEmpty)
          AlertBox(editable
              ? 'Bibliothèque vide. Ajoutez vos ouvrages, partez d\'un modèle (menu ⋮) ou importez un fichier CSV.'
              : 'Aucun élément.'),
        ...items,
      ]),
    );
  }
}

String baseLabel(QuantityBase base, String? countKey) =>
    base == QuantityBase.count ? 'Comptage : ${kCountItems[countKey]?.$2 ?? '?'}' : kBaseLabel[base]!;

/// Champ de prix pouvant rester vide (= « à renseigner », jamais 0 par défaut).
class MoneyField extends StatefulWidget {
  const MoneyField({super.key, required this.label, required this.cents, required this.onChanged, this.enabled = true, this.suffix});
  final String label;
  final int? cents;
  final ValueChanged<int?> onChanged;
  final bool enabled;
  final String? suffix;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.cents == null ? '' : (widget.cents! / 100).toStringAsFixed(2).replaceAll('.', ','),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        enabled: widget.enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        textAlign: TextAlign.right,
        decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix, hintText: 'à renseigner'),
        onChanged: (t) {
          if (t.trim().isEmpty) {
            widget.onChanged(null);
            return;
          }
          final v = parseNum(t);
          if (v != null) widget.onChanged((v * 100).round());
        },
      );
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged, this.enabled = true});
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: DropdownButtonFormField<T>(
          initialValue: items.containsKey(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final e in items.entries) DropdownMenuItem<T>(value: e.key, child: Text(e.value))],
          onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
        ),
      );
}

Widget _deleteButton(BuildContext context, AppState s, Syncable item, String what) => TextButton(
      onPressed: () async {
        if (await confirm(context, 'Supprimer $what ?', 'La suppression s\'appliquera à toute l\'équipe.', ok: 'Supprimer')) {
          s.deleteLibrary(item);
          if (context.mounted) Navigator.pop(context);
        }
      },
      child: Text('Supprimer $what'),
    );

/// Fiche ouvrage.
class WorkItemScreen extends StatelessWidget {
  const WorkItemScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final w = s.workItem(id);
    if (w == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Ouvrage introuvable.')));
    final on = canEditLibrary(context);
    final isAdmin = context.watch<SessionController>().user?.isAdmin ?? false;
    void edit(VoidCallback f) => s.editLibrary(w, f);

    return Scaffold(
      appBar: AppBar(title: const Text('Ouvrage'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (w.syncError != null) AlertBox('Envoi refusé : ${w.syncError}', kind: AlertKind.error),
        Row(children: [
          Expanded(child: EditField(key: ValueKey('c-$id'), label: 'Code', value: w.code, enabled: on, onChanged: (v) => edit(() => w.code = v))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _Dropdown<String>(label: 'Lot', value: w.category, items: kCategories, enabled: on, onChanged: (v) => edit(() => w.category = v)),
          ),
        ]),
        EditField(key: ValueKey('n-$id'), label: 'Désignation', value: w.name, enabled: on, onChanged: (v) => edit(() => w.name = v)),
        EditField(key: ValueKey('d-$id'), label: 'Description', value: w.description, maxLines: 3, enabled: on, onChanged: (v) => edit(() => w.description = v)),
        Row(children: [
          Expanded(child: _Dropdown<String>(label: 'Unité', value: w.unit, items: kUnitLabels, enabled: on, onChanged: (v) => edit(() => w.unit = v))),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: _Dropdown<QuantityBase>(
              label: 'Quantité calculée depuis',
              value: w.base,
              items: kBaseLabel,
              enabled: on,
              onChanged: (v) => edit(() {
                w.base = v;
                w.countKey = v == QuantityBase.count ? (w.countKey ?? kCountItems.keys.first) : null;
              }),
            ),
          ),
        ]),
        if (w.base == QuantityBase.count)
          _Dropdown<String>(
            label: 'Élément compté dans les pièces',
            value: w.countKey ?? kCountItems.keys.first,
            items: {for (final e in kCountItems.entries) e.key: e.value.$2},
            enabled: on,
            onChanged: (v) => edit(() => w.countKey = v),
          ),
        NumField(
          key: ValueKey('p-$id'),
          label: 'Taux de perte',
          suffix: '%',
          decimals: 1,
          enabled: on,
          value: w.wasteRateBp / 100,
          onChanged: (v) => edit(() => w.wasteRateBp = (v * 100).round().clamp(0, 10000)),
        ),
        Text('0 % par défaut. Un taux non nul est affiché sur chaque ligne de métré et de devis.',
            style: Theme.of(context).textTheme.bodySmall),
        const SectionHeader('Prix'),
        _Dropdown<String>(label: 'Devise', value: w.currency, items: const {'MAD': 'Dirham (MAD)', 'EUR': 'Euro (EUR)'}, enabled: on, onChanged: (v) => edit(() => w.currency = v)),
        Row(children: [
          Expanded(
            child: MoneyField(
              key: ValueKey('sp-$id'),
              label: 'Prix de vente HT',
              suffix: '/ ${w.unitLabel}',
              cents: w.salePriceCents,
              enabled: on,
              onChanged: (v) => edit(() => w.salePriceCents = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: MoneyField(
              key: ValueKey('lc-$id'),
              label: 'Main-d\'œuvre',
              suffix: '/ ${w.unitLabel}',
              cents: w.labourCostCents,
              enabled: on,
              onChanged: (v) => edit(() => w.labourCostCents = v),
            ),
          ),
        ]),
        EditField(key: ValueKey('pn-$id'), label: 'Source du prix (devis fournisseur, date…)', value: w.priceNote, enabled: on, onChanged: (v) => edit(() => w.priceNote = v)),
        if (isAdmin && w.serverVersion != null)
          TextButton.icon(
            onPressed: () => showPriceHistory(context, 'work_items', w.id, w.currency),
            icon: const Icon(Icons.history),
            label: const Text('Historique des prix'),
          ),
        SectionHeader('Composition (matériaux par ${w.unitLabel})',
            trailing: on && s.materials.isNotEmpty
                ? TextButton(
                    onPressed: () async {
                      final m = await showModalBottomSheet<MaterialItem>(
                        context: context,
                        builder: (_) => ListView(children: [
                          for (final m in s.materials) ListTile(title: Text(m.name), subtitle: Text(m.unitLabel), onTap: () => Navigator.pop(context, m)),
                        ]),
                      );
                      if (m != null) edit(() => w.components.add({'material_id': m.id, 'quantity_per_unit': 1.0}));
                    },
                    child: const Text('+ Matériau'),
                  )
                : null),
        if (w.components.isEmpty) Text('Aucun matériau rattaché.', style: Theme.of(context).textTheme.bodySmall),
        for (final (i, c) in w.components.indexed)
          Row(children: [
            Expanded(flex: 3, child: Text(s.material(c['material_id'] as String?)?.name ?? 'Matériau supprimé')),
            Expanded(
              flex: 2,
              child: NumField(
                key: ValueKey('cq-$id-$i'),
                label: 'Quantité',
                decimals: 3,
                enabled: on,
                value: (c['quantity_per_unit'] as num).toDouble(),
                onChanged: (v) => edit(() => c['quantity_per_unit'] = v),
              ),
            ),
            if (on) IconButton(onPressed: () => edit(() => w.components.removeAt(i)), icon: const Icon(Icons.close)),
          ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Proposé dans les devis'),
          value: w.active,
          onChanged: on ? (v) => edit(() => w.active = v) : null,
        ),
        if (on) ...[
          TextButton(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute<void>(builder: (_) => WorkItemScreen(id: s.duplicateWorkItem(w).id))), child: const Text('Dupliquer')),
          _deleteButton(context, s, w, 'cet ouvrage'),
        ],
      ]),
    );
  }
}

/// Fiche matériau.
class MaterialScreen extends StatelessWidget {
  const MaterialScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final m = s.material(id);
    if (m == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Matériau introuvable.')));
    final on = canEditLibrary(context);
    final isAdmin = context.watch<SessionController>().user?.isAdmin ?? false;
    void edit(VoidCallback f) => s.editLibrary(m, f);

    return Scaffold(
      appBar: AppBar(title: const Text('Matériau'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (m.syncError != null) AlertBox('Envoi refusé : ${m.syncError}', kind: AlertKind.error),
        EditField(key: ValueKey('n-$id'), label: 'Désignation', value: m.name, enabled: on, onChanged: (v) => edit(() => m.name = v)),
        _Dropdown<String>(label: 'Lot', value: m.category, items: kCategories, enabled: on, onChanged: (v) => edit(() => m.category = v)),
        Row(children: [
          Expanded(child: EditField(key: ValueKey('b-$id'), label: 'Marque', value: m.brand, enabled: on, onChanged: (v) => edit(() => m.brand = v))),
          const SizedBox(width: 8),
          Expanded(child: EditField(key: ValueKey('r-$id'), label: 'Référence', value: m.reference, enabled: on, onChanged: (v) => edit(() => m.reference = v))),
        ]),
        _Dropdown<String?>(
          label: 'Fournisseur',
          value: m.supplierId,
          items: {null: 'Aucun', for (final x in s.suppliers) x.id: x.name},
          enabled: on,
          onChanged: (v) => edit(() => m.supplierId = v),
        ),
        Row(children: [
          Expanded(child: _Dropdown<String>(label: 'Unité', value: m.unit, items: kUnitLabels, enabled: on, onChanged: (v) => edit(() => m.unit = v))),
          const SizedBox(width: 8),
          Expanded(
            child: NumField(
              key: ValueKey('pk-$id'),
              label: 'Conditionnement',
              suffix: m.unitLabel,
              decimals: 3,
              enabled: on,
              value: m.packSize ?? 0,
              onChanged: (v) => edit(() => m.packSize = v <= 0 ? null : v),
            ),
          ),
        ]),
        NumField(
          key: ValueKey('w-$id'),
          label: 'Taux de perte',
          suffix: '%',
          decimals: 1,
          enabled: on,
          value: m.wasteRateBp / 100,
          onChanged: (v) => edit(() => m.wasteRateBp = (v * 100).round().clamp(0, 10000)),
        ),
        const SectionHeader('Prix'),
        _Dropdown<String>(label: 'Devise', value: m.currency, items: const {'MAD': 'Dirham (MAD)', 'EUR': 'Euro (EUR)'}, enabled: on, onChanged: (v) => edit(() => m.currency = v)),
        Row(children: [
          if (isAdmin || context.watch<SessionController>().isDemo) ...[
            Expanded(
              child: MoneyField(
                key: ValueKey('pp-$id'),
                label: 'Prix d\'achat HT',
                suffix: '/ ${m.unitLabel}',
                cents: m.purchasePriceCents,
                enabled: on,
                onChanged: (v) => edit(() => m.purchasePriceCents = v),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: MoneyField(
              key: ValueKey('sp-$id'),
              label: 'Prix de vente HT',
              suffix: '/ ${m.unitLabel}',
              cents: m.salePriceCents,
              enabled: on,
              onChanged: (v) => edit(() => m.salePriceCents = v),
            ),
          ),
        ]),
        Row(children: [
          Expanded(child: EditField(key: ValueKey('ci-$id'), label: 'Ville', value: m.city, enabled: on, onChanged: (v) => edit(() => m.city = v))),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: EditField(key: ValueKey('pn-$id'), label: 'Source du prix', value: m.priceNote, enabled: on, onChanged: (v) => edit(() => m.priceNote = v))),
        ]),
        if (isAdmin && m.serverVersion != null)
          TextButton.icon(
            onPressed: () => showPriceHistory(context, 'materials', m.id, m.currency),
            icon: const Icon(Icons.history),
            label: const Text('Historique des prix'),
          ),
        if (on) _deleteButton(context, s, m, 'ce matériau'),
      ]),
    );
  }
}

/// Fiche fournisseur.
class SupplierScreen extends StatelessWidget {
  const SupplierScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final x = s.supplier(id);
    if (x == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Fournisseur introuvable.')));
    final on = canEditLibrary(context);
    void edit(VoidCallback f) => s.editLibrary(x, f);
    return Scaffold(
      appBar: AppBar(title: const Text('Fournisseur'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (x.syncError != null) AlertBox('Envoi refusé : ${x.syncError}', kind: AlertKind.error),
        EditField(key: ValueKey('n-$id'), label: 'Raison sociale', value: x.name, enabled: on, onChanged: (v) => edit(() => x.name = v)),
        EditField(key: ValueKey('c-$id'), label: 'Contact', value: x.contactName, enabled: on, onChanged: (v) => edit(() => x.contactName = v)),
        EditField(key: ValueKey('p-$id'), label: 'Téléphone', value: x.phone, keyboardType: TextInputType.phone, enabled: on, onChanged: (v) => edit(() => x.phone = v)),
        EditField(key: ValueKey('e-$id'), label: 'E-mail', value: x.email, keyboardType: TextInputType.emailAddress, enabled: on, onChanged: (v) => edit(() => x.email = v)),
        EditField(key: ValueKey('a-$id'), label: 'Adresse', value: x.address, enabled: on, onChanged: (v) => edit(() => x.address = v)),
        EditField(key: ValueKey('v-$id'), label: 'Ville', value: x.city, enabled: on, onChanged: (v) => edit(() => x.city = v)),
        EditField(key: ValueKey('i-$id'), label: 'ICE (15 chiffres)', value: x.ice, keyboardType: TextInputType.number, maxLength: 15, enabled: on, onChanged: (v) => edit(() => x.ice = v)),
        EditField(key: ValueKey('o-$id'), label: 'Notes', value: x.notes, maxLines: 3, enabled: on, onChanged: (v) => edit(() => x.notes = v)),
        if (on) _deleteButton(context, s, x, 'ce fournisseur'),
      ]),
    );
  }
}

/// Historique des prix (administrateur, connexion requise).
Future<void> showPriceHistory(BuildContext context, String kind, String id, String currency) async {
  final api = context.read<SessionController>().api;
  List<dynamic>? rows;
  String? error;
  try {
    rows = await api.get('/library/price-history/$kind/$id') as List;
  } on ApiException catch (e) {
    error = e.message;
  }
  if (!context.mounted) return;
  String money(Object? c) => c == null ? '—' : (currency == 'EUR' ? eur(c as int) : dh(c as int));
  await showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Historique des prix', style: Theme.of(context).textTheme.titleMedium),
        if (error != null) AlertBox(error, kind: AlertKind.error),
        if (rows != null && rows.isEmpty) const Text('Aucun prix enregistré.'),
        for (final r in rows ?? const [])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(frDate(DateTime.parse((r as Map)['recorded_at'] as String).toLocal())),
            subtitle: Text([
              'vente ${money(r['sale_price_cents'])}',
              if (r['purchase_price_cents'] != null) 'achat ${money(r['purchase_price_cents'])}',
              if (r['labour_cost_cents'] != null) 'main-d\'œuvre ${money(r['labour_cost_cents'])}',
              if ((r['source_note'] as String).isNotEmpty) r['source_note'],
            ].join(' · ')),
          ),
      ]),
    ),
  );
}

/// Import d'un fichier CSV collé (copié depuis un tableur). Tout ou rien, erreurs par ligne.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  static const _headers = {
    'work_items': 'code;categorie;designation;description;unite;base;element_compte;perte_pct;prix_vente;main_oeuvre',
    'materials': 'designation;categorie;marque;reference;unite;conditionnement;perte_pct;prix_achat;prix_vente;fournisseur;ville',
  };
  String _kind = 'work_items';
  final _text = TextEditingController();
  final _note = TextEditingController(text: 'Import CSV');
  bool _busy = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    final session = context.read<SessionController>();
    try {
      final r = Map<String, dynamic>.from(await session.api.post('/library/import', {
        'kind': _kind,
        'csv': _text.text,
        'price_note': _note.text.trim().isEmpty ? 'Import CSV' : _note.text.trim(),
      }) as Map);
      if (!mounted) return;
      setState(() => _result = r);
      if ((r['errors'] as List).isEmpty && mounted) {
        await context.read<SyncEngine>().syncNow();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final errors = (_result?['errors'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Importer un fichier CSV')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'work_items', label: Text('Ouvrages')),
            ButtonSegment(value: 'materials', label: Text('Matériaux')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: 8),
        const Text('Copiez les lignes depuis votre tableur (première ligne = en-têtes) et collez-les ci-dessous. '
            'Colonnes attendues, séparées par des points-virgules ou des tabulations :'),
        SelectableText(_headers[_kind]!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        const Text('Un prix vide reste « à renseigner ». Si une seule ligne est fausse, rien n\'est importé.'),
        const SizedBox(height: 8),
        TextField(controller: _text, maxLines: 10, decoration: const InputDecoration(labelText: 'Contenu CSV')),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Source des prix (enregistrée dans l\'historique)')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _send, child: const Text('Importer')),
        if (_error != null) AlertBox(_error!, kind: AlertKind.error),
        if (_result != null && errors.isEmpty) AlertBox('${_result!['created']} élément(s) importé(s).'),
        if (errors.isNotEmpty) ...[
          AlertBox('Rien n\'a été importé : ${errors.length} ligne(s) à corriger.', kind: AlertKind.error),
          for (final e in errors) Text('Ligne ${(e as Map)['line']} : ${e['message']}'),
        ],
      ]),
    );
  }
}
