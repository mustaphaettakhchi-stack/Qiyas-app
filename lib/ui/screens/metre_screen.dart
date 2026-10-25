import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../data/app_state.dart';
import '../../domain/calculations.dart';
import '../widgets/common.dart';
import 'quote_screen.dart';

/// E7 · Métré automatique, par pièce et total.
class MetreScreen extends StatelessWidget {
  const MetreScreen({super.key, required this.projectId});
  final String projectId;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.project(projectId);
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Projet introuvable.')));
    final total = projectMeasures(p);
    const numStyle = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    const bold = TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]);

    DataRow row(String name, Measures m, {bool isTotal = false}) {
      final st = isTotal ? bold : numStyle;
      return DataRow(cells: [
        DataCell(Text(name, style: isTotal ? bold : null)),
        DataCell(Text(fmt2(m.floor), style: st)),
        DataCell(Text(fmt2(m.ceiling), style: st)),
        DataCell(Text(fmt2(m.walls), style: st)),
        DataCell(Text(fmt2(m.skirting), style: st)),
        DataCell(Text(fmt2(m.volume), style: st)),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Métré'), actions: const [SyncBadge()]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          'Calcul automatique : murs nets d\'ouvertures, plinthes hors largeur des portes.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 18,
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: const [
              DataColumn(label: Text('Pièce')),
              DataColumn(label: Text('Sol m²'), numeric: true),
              DataColumn(label: Text('Plafond m²'), numeric: true),
              DataColumn(label: Text('Murs m²'), numeric: true),
              DataColumn(label: Text('Plinthes ml'), numeric: true),
              DataColumn(label: Text('Volume m³'), numeric: true),
            ],
            rows: [
              for (final r in p.rooms) row(r.name, roomMeasures(r)),
              row('Total', total, isTotal: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () {
            final q = s.draftQuoteFor(p);
            Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteScreen(projectId: p.id, quoteId: q.id)));
          },
          child: const Text('Passer au devis'),
        ),
      ]),
    );
  }
}
