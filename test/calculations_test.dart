import 'package:flutter_test/flutter_test.dart';
import 'package:qiyas/core/format.dart';
import 'package:qiyas/data/sample_data.dart';
import 'package:qiyas/domain/calculations.dart';
import 'package:qiyas/domain/models.dart';

/// Cas de test de référence du cahier des charges (section « Règles de calcul »).
void main() {
  Project referenceProject() {
    final pres = samplePrestations();
    Prestation byId(String id) => pres.firstWhere((p) => p.id == id);
    return Project(
      id: 'ref',
      rooms: referenceRooms(),
      quotes: [
        Quote(
          id: 'q',
          number: 'DV-TEST-0001',
          date: DateTime(2026, 10, 25),
          depositPercent: 30,
          lines: [for (final id in ['pm', 'pp', 'cs', 'pl']) lineFrom(byId(id), id)],
        ),
      ],
    );
  }

  group('Métré', () {
    test('une pièce simple', () {
      final r = Room(id: 'a', name: 'Test', length: 4, width: 3, height: 2.5, openings: [
        Opening.standard('d', OpeningType.door),
        Opening.standard('w', OpeningType.window),
      ]);
      final m = roomMeasures(r);
      expect(m.perimeter, closeTo(14, 1e-9));
      expect(m.floor, closeTo(12, 1e-9));
      expect(m.walls, closeTo(14 * 2.5 - 0.83 * 2.04 - 1.2 * 1.25, 1e-9));
      expect(m.skirting, closeTo(14 - 0.83, 1e-9));
      expect(m.volume, closeTo(30, 1e-9));
    });

    test('jamais négatif', () {
      final r = Room(id: 'b', name: 'Placard', length: 0.5, width: 0.5, height: 2, openings: [
        Opening.standard('d1', OpeningType.door),
        Opening.standard('d2', OpeningType.door),
        Opening.standard('d3', OpeningType.door),
      ]);
      final m = roomMeasures(r);
      expect(m.walls, 0);
      expect(m.skirting, 0);
    });

    test('projet de référence : 51,66 m² de sol, 163,03 m² de murs, 60,08 ml de plinthes', () {
      final m = projectMeasures(referenceProject());
      expect(m.floor, 51.66);
      expect(m.ceiling, 51.66);
      expect(m.walls, 163.03);
      expect(m.skirting, 60.08);
    });
  });

  group('Devis', () {
    test('référence : 27 989 MAD HT, 5 598 MAD de TVA, 33 587 MAD TTC', () {
      final p = referenceProject();
      final t = quoteTotals(p, p.quotes.first, 20);
      expect(t.ht, 2798895);
      expect(t.vat, 559779);
      expect(t.ttc, 3358674);
      expect(dh(t.ht), '27 989 DH');
      expect(dh(t.vat), '5 598 DH');
      expect(dh(t.ttc), '33 587 DH');
      expect(t.deposit, 1007602);
    });

    test('une quantité saisie à la main ne suit plus le métré', () {
      final p = referenceProject();
      final line = p.quotes.first.lines.first;
      line
        ..manual = true
        ..quantity = 10;
      expect(lineQuantity(p, line), 10);
      expect(lineTotalCents(p, line), 45000);
    });

    test('un devis figé ne bouge plus quand le relevé change', () {
      final p = referenceProject();
      final q = p.quotes.first;
      for (final l in q.lines) {
        l.frozenQuantity = lineQuantity(p, l);
      }
      final before = quoteTotals(p, q, 20).ttc;
      p.rooms.first.length = 10;
      expect(quoteTotals(p, q, 20).ttc, before);
    });

    test('la remise s\'applique avant la TVA', () {
      final p = referenceProject();
      final q = p.quotes.first..discountPercent = 10;
      final t = quoteTotals(p, q, 20);
      expect(t.discount, (t.subtotal * 0.10).round());
      expect(t.ht, t.subtotal - t.discount);
      expect(t.vat, (t.ht * 0.20).round());
    });
  });

  group('Formats', () {
    test('nombres et montants', () {
      expect(fmt2(1234.5), '1 234,50');
      expect(fmt2(0.05), '0,05');
      expect(dh(123456789), '1 234 568 DH');
      expect(parseNum('5,20'), 5.2);
      expect(parseNum('abc'), isNull);
      expect(frDate(DateTime(2026, 3, 7)), '07/03/2026');
    });

    test('numéro WhatsApp marocain', () {
      expect(waNumber('0661234567'), '212661234567');
      expect(waNumber('+212 6 61 23 45 67'), '212661234567');
      expect(waNumber('661234567'), '212661234567');
    });
  });

  group('Sauvegarde', () {
    test('les données survivent à un aller-retour JSON', () {
      final data = sampleData();
      final back = AppData.fromJson(data.toJson());
      expect(back.projects.length, data.projects.length);
      final p = back.projects.first;
      expect(quoteTotals(p, p.quotes.first, back.company.vatPercent).ttc, 3358674);
      expect(back.company.hasValidIce, isTrue);
    });
  });
}
