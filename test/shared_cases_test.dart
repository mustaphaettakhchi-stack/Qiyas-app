import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/domain/calculations.dart';
import 'package:lamaalam/domain/geometry.dart';
import 'package:lamaalam/domain/models.dart';

/// Cas de métré partagés avec le serveur (backend/tests/test_geometry.py).
void main() {
  final cases = (jsonDecode(File('shared/metre_cases.json').readAsStringSync()) as Map)['cases'] as List;

  for (final raw in cases) {
    final c = Map<String, dynamic>.from(raw as Map);
    test(c['name'] as String, () {
      final walls = (c['walls'] as List).cast<List>();
      final room = Room(
        id: 'r',
        name: 'cas',
        height: (c['height'] as num).toDouble(),
        walls: [
          for (var i = 0; i < walls.length; i++)
            Wall(id: 'w$i', length: (walls[i][0] as num).toDouble(), angle: (walls[i][1] as num).toDouble()),
        ],
        openings: [
          for (final o in (c['openings'] as List).cast<List>())
            Opening(
              id: 'o',
              type: o[0] == 'door' ? OpeningType.door : OpeningType.window,
              wallIndex: o[1] as int,
              width: (o[2] as num).toDouble(),
              height: (o[3] as num).toDouble(),
            ),
        ],
      );
      final m = roomMeasures(room);
      final shape = outline([for (final w in room.walls) w.length], [for (final w in room.walls) w.angle]);
      final e = Map<String, dynamic>.from(c['expected'] as Map);
      expect(m.perimeter, closeTo((e['perimeter'] as num).toDouble(), 1e-6), reason: 'périmètre');
      expect(m.floor, closeTo((e['floor'] as num).toDouble(), 1e-6), reason: 'sol');
      expect(m.walls, closeTo((e['walls'] as num).toDouble(), 1e-6), reason: 'murs nets');
      expect(m.skirting, closeTo((e['skirting'] as num).toDouble(), 1e-6), reason: 'plinthes');
      expect(m.volume, closeTo((e['volume'] as num).toDouble(), 1e-6), reason: 'volume');
      expect(shape.closureError, closeTo((e['closure'] as num).toDouble(), 1e-6), reason: 'fermeture');
      expect(shape.closes, e['closes']);
    });
  }

  test('Croisement de murs détecté', () {
    final bow = outline([5, 3, 5, 3], [306.86989764584405, 306.86989764584405, 53.13010235415598, 53.13010235415598]);
    expect(bow.closes, isTrue);
    expect(bow.selfIntersecting, isTrue);
    expect(outline([6, 2, 2, 2, 4, 4], [90, 90, 270, 90, 90, 90]).selfIntersecting, isFalse);
  });

  group('Cas de devis partagés avec le serveur', () {
    final quoteCases = (jsonDecode(File('shared/quote_cases.json').readAsStringSync()) as Map)['cases'] as List;
    for (final raw in quoteCases) {
      final c = Map<String, dynamic>.from(raw as Map);
      test(c['name'] as String, () {
        final q = Quote(id: 'q', date: DateTime(2026))
          ..overheadBp = c['overhead_bp'] as int
          ..marginBp = c['margin_bp'] as int;
        final lines = [
          for (final raw in c['lines'] as List)
            (() {
              final l = Map<String, dynamic>.from(raw as Map);
              final line = QuoteLine(
                id: 'l',
                label: 'x',
                pricing: l['pricing'] as String,
                unitPriceCents: (l['unit_price_cents'] as int?) ?? 0,
                materialCostCents: l['material_cost_cents'] as int?,
                labourCostCents: l['labour_cost_cents'] as int?,
                vatRateBp: l['vat_rate_bp'] as int,
              );
              return ((l['quantity'] as num).toDouble(), lineUnitPriceCents(q, line), line.vatRateBp);
            })(),
        ];
        final t = computeTotals(lines, c['discount_bp'] as int, c['deposit_bp'] as int);
        final e = Map<String, dynamic>.from(c['expected'] as Map);
        expect([for (final (qty, price, _) in lines) lineAmountCents(qty, price!)], e['line_totals']);
        if (e.containsKey('unit_prices')) expect([for (final (_, price, _) in lines) price], e['unit_prices']);
        expect([t.subtotal, t.discount, t.ht, t.vat, t.ttc, t.deposit],
            [e['subtotal'], e['discount'], e['ht'], e['vat_total'], e['ttc'], e['deposit']]);
        expect(t.toServer()['vat'], e['vat']);
      });
    }
  });
}
