import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/templates.dart';
import 'package:lamaalam/domain/calculations.dart';
import 'package:lamaalam/domain/metre.dart';
import 'package:lamaalam/domain/models.dart';

Room _salon() => Room.rectangle(id: 'r1', name: 'Salon', length: 5, width: 4, height: 2.5)
  ..counts = {'prises': 6, 'points_lumineux': 2};

Room _cuisine() => Room.rectangle(id: 'r2', name: 'Cuisine', length: 3, width: 3, height: 2.5)
  ..counts = {'prises': 4, 'points_eau': 2};

void main() {
  group('Métré par lot', () {
    test('Éléments comptés additionnés pièce par pièce', () {
      final m = projectMeasures(Project(id: 'p', rooms: [_salon(), _cuisine()]));
      expect(m.counts['prises'], 10);
      expect(m.counts['points_eau'], 2);
      expect(m.of(QuantityBase.count, 'points_lumineux'), 2);
      expect(m.of(QuantityBase.count, 'sanitaires'), 0);
    });

    test('Murs bruts, ouvertures, portes et fenêtres', () {
      final r = Room.rectangle(id: 'r', name: 'R', length: 4, width: 3, height: 2.5, openings: [
        Opening(id: 'd', type: OpeningType.door, width: 0.9, height: 2),
        Opening(id: 'w', type: OpeningType.window, width: 1, height: 1),
      ]);
      final m = roomMeasures(r);
      expect(m.wallsGross, closeTo(35, 1e-9));
      expect(m.openingsArea, closeTo(2.8, 1e-9));
      expect(m.walls, closeTo(32.2, 1e-9));
      expect(m.doors, 1);
      expect(m.windows, 1);
    });
  });

  group('Perte', () {
    test('Appliquée à la quantité du métré, affichable, jamais implicite', () {
      final p = Project(id: 'p', rooms: [_salon()]); // sol 20 m²
      final w = WorkItem(id: 'w', name: 'Carrelage', unit: 'm2', base: QuantityBase.floor, wasteRateBp: 1000, salePriceCents: 25000);
      final line = lineFrom(w, 'l');
      expect(lineNetQuantity(p, line), 20);
      expect(lineQuantity(p, line), 22);
      expect(lineTotalCents(p, line), 22 * 25000);
      expect(WorkItem(id: 'x', name: 'x').wasteRateBp, 0);
    });

    test('Quantité saisie à la main : pas de perte ajoutée', () {
      final p = Project(id: 'p', rooms: [_salon()]);
      final line = lineFrom(WorkItem(id: 'w', name: 'x', base: QuantityBase.floor, wasteRateBp: 1000), 'l')
        ..manual = true
        ..quantity = 18;
      expect(lineQuantity(p, line), 18);
    });

    test('Ouvrage compté : prises du métré', () {
      final p = Project(id: 'p', rooms: [_salon(), _cuisine()]);
      final line = lineFrom(WorkItem(id: 'w', name: 'Prise', base: QuantityBase.count, countKey: 'prises', unit: 'u'), 'l');
      expect(lineQuantity(p, line), 10);
      expect(line.priceMissing, isTrue);
    });
  });

  group('Validation du métré', () {
    test('Empreinte : change avec une cote, pas avec un nom', () {
      final p = Project(id: 'p', rooms: [_salon()]);
      final before = metreFingerprint(p);
      p.rooms.first.name = 'Séjour';
      expect(metreFingerprint(p), before);
      p.rooms.first.walls.first.length = 5.1;
      expect(metreFingerprint(p), isNot(before));
      p.rooms.first.walls.first.length = 5;
      p.rooms.first.counts['prises'] = 7;
      expect(metreFingerprint(p), isNot(before));
    });

    test('Validé, puis périmé après modification', () {
      final p = Project(id: 'p', rooms: [_salon()]);
      expect(metreState(p), MetreState.notValidated);
      p.metreValidation = buildValidation(p, userId: 'u', userName: 'Karim');
      expect(metreState(p), MetreState.validated);
      p.rooms.first.height = 2.6;
      expect(metreState(p), MetreState.stale);
    });

    test('Cotes standard listées ; pièce non fermée bloquante', () {
      final r = Room.rectangle(id: 'r', name: 'Chambre', length: 4, width: 3, height: 2.8, openings: [
        Opening.standard('d', OpeningType.door),
      ])..heightSource = MeasureSource.standard;
      final p = Project(id: 'p', rooms: [r]);
      expect(unverifiedMeasures(p).map((u) => u.label), ['hauteur', 'largeur de la porte', 'hauteur de la porte']);
      expect(blockingRooms(p), isEmpty);
      r.walls[2].length = 4.1;
      expect(blockingRooms(p), [r]);
    });
  });

  group('Reprise des prestations Qiyas', () {
    test('Prix nul = non renseigné, unités converties', () {
      final data = AppData.fromJson({
        'company': <String, dynamic>{},
        'prestations': [
          {'id': 'a', 'name': 'Peinture', 'unit': 'm²', 'base': 'walls', 'pu': 4500},
          {'id': 'b', 'name': 'Plinthes', 'unit': 'ml', 'base': 'skirting', 'pu': 0},
        ],
      });
      expect(data.workItems.map((w) => w.unit), ['m2', 'm']);
      expect(data.workItems.map((w) => w.salePriceCents), [4500, null]);
      expect(data.workItems.first.base, QuantityBase.walls);
    });
  });
}
