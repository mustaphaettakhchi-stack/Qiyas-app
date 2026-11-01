import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../../domain/metre.dart';
import '../../domain/models.dart';
import '../../session/session_controller.dart';
import '../widgets/common.dart';
import 'quote_screen.dart';
import 'room_screen.dart';

/// Une grandeur du métré : libellé, unité, valeur dans une pièce, explication du calcul.
class _Quantity {
  const _Quantity(this.label, this.unit, this.value, this.explain);
  final String label;
  final String unit;
  final double Function(Measures m) value;
  final String Function(Room r, Measures m) explain;
}

String _f(double v) => fmt2(v);

final Map<String, List<_Quantity>> _sections = {
  'Sols': [
    _Quantity('Surface de sol', 'm²', (m) => m.floor,
        (r, m) => 'Aire du contour de ${r.walls.length} murs (formule du lacet) = ${_f(m.floor)} m².'),
    _Quantity('Plinthes', 'm', (m) => m.skirting,
        (r, m) => 'Périmètre ${_f(m.perimeter)} m − largeur des portes ${_f(m.perimeter - m.skirting)} m = ${_f(m.skirting)} m.'),
  ],
  'Murs': [
    _Quantity('Surface brute', 'm²', (m) => m.wallsGross,
        (r, m) => 'Périmètre ${_f(m.perimeter)} m × hauteur ${_f(r.height)} m = ${_f(m.wallsGross)} m².'),
    _Quantity('Ouvertures', 'm²', (m) => m.openingsArea,
        (r, m) => r.openings.isEmpty
            ? 'Aucune ouverture.'
            : '${r.openings.map((o) => '${o.type == OpeningType.door ? 'porte' : 'fenêtre'} ${_f(o.width)} × ${_f(o.height)}').join(' + ')}'
                ' = ${_f(m.openingsArea)} m².'),
    _Quantity('Surface nette', 'm²', (m) => m.walls,
        (r, m) => 'Pour chaque mur : longueur × hauteur − ses ouvertures (jamais négatif), additionnés = ${_f(m.walls)} m².'),
  ],
  'Plafonds': [
    _Quantity('Surface de plafond', 'm²', (m) => m.ceiling, (r, m) => 'Égale à la surface de sol : ${_f(m.ceiling)} m².'),
  ],
  'Menuiseries': [
    _Quantity('Portes', 'u', (m) => m.doors, (r, m) => '${r.doorCount} porte(s) saisie(s) dans la pièce.'),
    _Quantity('Fenêtres', 'u', (m) => m.windows, (r, m) => '${r.windowCount} fenêtre(s) saisie(s) dans la pièce.'),
  ],
  'Volumes': [
    _Quantity('Volume', 'm³', (m) => m.volume,
        (r, m) => 'Surface de sol ${_f(m.floor)} m² × hauteur ${_f(r.height)} m = ${_f(m.volume)} m³.'),
  ],
};

/// Métré par lot et par pièce, explication de chaque quantité, validation.
class MetreScreen extends StatelessWidget {
  const MetreScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Projet introuvable.')));
    final perRoom = [for (final r in p.rooms) (r, roomMeasures(r))];
    final total = projectMeasures(p);
    final t = Theme.of(context).textTheme;

    // Éléments comptés, regroupés par lot.
    final countSections = <String, List<String>>{};
    for (final e in kCountItems.entries) {
      if (total.counts[e.key] != null && total.counts[e.key]! > 0) {
        countSections.putIfAbsent(kCategories[e.value.$1]!, () => []).add(e.key);
      }
    }

    void explain(String title, String text) => showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(title),
            content: Text(text),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Fermer'))],
          ),
        );

    Widget section(String title, List<Widget> rows) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.titleMedium),
              ...rows,
            ]),
          ),
        );

    Widget line(String label, String value, {bool strong = false, VoidCallback? onTap}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(child: Text(label, style: strong ? t.bodyMedium?.copyWith(fontWeight: FontWeight.w700) : null)),
              Text(value,
                  style: TextStyle(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: strong ? FontWeight.w700 : null,
                  )),
              if (onTap != null) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.info_outline, size: 16)),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Métré'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _ValidationCard(project: p),
        const SizedBox(height: 8),
        Text('Touchez une valeur pour voir son calcul. Les coefficients de perte s\'appliquent dans le devis, '
            'ouvrage par ouvrage, et y sont affichés.', style: t.bodySmall),
        for (final e in _sections.entries)
          section(e.key, [
            for (final q in e.value) ...[
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(q.label, style: t.labelLarge)),
              for (final (r, m) in perRoom)
                line('  ${r.name}', '${_f(q.value(m))} ${q.unit}', onTap: () => explain('${q.label} · ${r.name}', q.explain(r, m))),
              line('  Total', '${_f(q.value(total))} ${q.unit}', strong: true),
            ],
          ]),
        for (final e in countSections.entries)
          section(e.key, [
            for (final key in e.value) ...[
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(kCountItems[key]!.$2, style: t.labelLarge)),
              for (final (r, m) in perRoom)
                if ((m.counts[key] ?? 0) > 0) line('  ${r.name}', '${_f(m.counts[key]!)} ${kUnitLabels[kCountItems[key]!.$3]}'),
              line('  Total', '${_f(total.counts[key]!)} ${kUnitLabels[kCountItems[key]!.$3]}', strong: true),
            ],
          ]),
        if (countSections.isEmpty)
          Text('Aucun élément compté (prises, points d\'eau, cloisons…) : renseignez-les dans chaque pièce.', style: t.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final q = s.draftQuoteFor(p);
            Navigator.push(context, MaterialPageRoute<void>(builder: (_) => QuoteScreen(projectId: p.id, quoteId: q.id)));
          },
          child: const Text('Passer au devis'),
        ),
      ]),
    );
  }
}

class _ValidationCard extends StatelessWidget {
  const _ValidationCard({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final session = context.watch<SessionController>();
    final p = project;
    final state = metreState(p);
    final blocking = blockingRooms(p);
    final unverified = unverifiedMeasures(p);
    final v = p.metreValidation;

    Future<void> validate() async {
      if (unverified.isNotEmpty) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => _AcceptUnverifiedDialog(items: unverified),
        );
        if (ok != true) return;
      }
      final user = session.user;
      s.mutate(
        () => p.metreValidation = buildValidation(p, userId: user?.id ?? '', userName: user?.fullName ?? ''),
        touch: p,
        meta: true,
      );
      if (context.mounted) showToast(context, 'Métré validé.');
    }

    final (String text, AlertKind kind) = switch (state) {
      MetreState.validated => (
          'Métré validé le ${frDate(DateTime.parse(v!['validated_at'] as String).toLocal())}'
              '${(v['validated_by_name'] as String? ?? '').isEmpty ? '' : ' par ${v['validated_by_name']}'}'
              '${(v['unverified_accepted'] as num? ?? 0) > 0 ? ', avec ${v['unverified_accepted']} cote(s) non vérifiée(s) acceptée(s)' : ''}.',
          AlertKind.info
        ),
      MetreState.stale => ('Des cotes ont changé depuis la validation : le métré est à revalider.', AlertKind.warning),
      MetreState.notValidated => ('Métré non validé.', AlertKind.warning),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AlertBox(text, kind: kind),
      if (blocking.isNotEmpty) ...[
        const SizedBox(height: 8),
        AlertBox(
          'Validation impossible : cotes incohérentes dans ${blocking.map((r) => r.name).join(', ')}.',
          kind: AlertKind.error,
          action: Wrap(spacing: 8, children: [
            for (final r in blocking)
              TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute<void>(builder: (_) => RoomScreen(projectId: p.id, roomId: r.id))),
                child: Text('Corriger ${r.name}'),
              ),
          ]),
        ),
      ],
      if (state != MetreState.validated && p.rooms.isNotEmpty && blocking.isEmpty) ...[
        const SizedBox(height: 8),
        FilledButton.tonal(
          onPressed: validate,
          child: Text(unverified.isEmpty ? 'Valider le métré' : 'Valider le métré (${unverified.length} cote(s) à vérifier)'),
        ),
      ],
    ]);
  }
}

class _AcceptUnverifiedDialog extends StatefulWidget {
  const _AcceptUnverifiedDialog({required this.items});
  final List<UnverifiedMeasure> items;

  @override
  State<_AcceptUnverifiedDialog> createState() => _AcceptUnverifiedDialogState();
}

class _AcceptUnverifiedDialogState extends State<_AcceptUnverifiedDialog> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cotes non vérifiées'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(shrinkWrap: true, children: [
            const Text('Ces cotes sont encore à leur valeur standard. Le mieux est de les mesurer sur place.'),
            const SizedBox(height: 8),
            for (final u in widget.items) Text('• ${u.room} : ${u.label}'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              title: const Text('J\'accepte de valider le métré avec ces valeurs non vérifiées'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: _accepted ? () => Navigator.pop(context, true) : null, child: const Text('Valider')),
        ],
      );
}
