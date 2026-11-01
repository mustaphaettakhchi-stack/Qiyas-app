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
}
