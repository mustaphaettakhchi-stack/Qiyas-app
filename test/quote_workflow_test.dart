import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/domain/calculations.dart';
import 'package:lamaalam/domain/metre.dart';
import 'package:lamaalam/domain/models.dart';

class _MemoryStore extends LocalStore {
  AppData? saved;
  @override
  Future<AppData?> load() async => saved;
  @override
  Future<void> save(AppData data) async => saved = data;
}

Future<(AppState, Project)> _setup() async {
  final s = AppState(store: _MemoryStore());
  await s.init();
  s.data.company
    ..ice = '001234567000089'
    ..vatPercent = 20;
  final p = s.createProject();
  final r = s.addRoom(p);
  s.mutate(() {
    for (final (i, l) in [5.0, 4.0, 5.0, 4.0].indexed) {
      r.walls[i]
        ..length = l
        ..lengthSource = MeasureSource.manual;
    }
    r.heightSource = MeasureSource.manual;
  }, touch: p, room: r);
  return (s, p);
}

void main() {
  test('Ligne depuis un ouvrage : TVA par défaut de l\'entreprise, perte et prix repris', () async {
    final (s, p) = await _setup();
    final q = s.createQuote(p);
    s.addLineFromWorkItem(p, q, WorkItem(id: 'w', name: 'Carrelage', unit: 'm2', base: QuantityBase.floor, wasteRateBp: 1000, salePriceCents: 25000));
    final l = q.lines.single;
    expect(l.vatRateBp, 2000);
    expect(lineQuantity(p, l), 22);
    expect(quoteTotals(p, q).ht, 22 * 25000);
  });

  test('Ouvrage défini par son coût : prix calculé avec frais et marge, sans prix de vente imposé', () async {
    final (s, p) = await _setup();
    final q = s.createQuote(p)
      ..overheadBp = 1000
      ..marginBp = 1500;
    s.addLineFromWorkItem(p, q, WorkItem(id: 'w', name: 'Pose', unit: 'u', base: QuantityBase.free, labourCostCents: 12000));
    final l = q.lines.single;
    expect(l.pricing, 'cost_plus');
    expect(lineUnitPriceCents(q, l), costPlusPriceCents(0, 12000, 1000, 1500));
  });

  test('Validation : conditions, quantités figées, nouvelle version qui remplace l\'ancienne', () async {
    final (s, p) = await _setup();
    final q = s.createQuote(p);
    s.addLineFromWorkItem(p, q, WorkItem(id: 'w', name: 'Peinture', unit: 'm2', base: QuantityBase.walls));
    final problems = s.validationProblems(p, q, isAdmin: false);
    expect(problems, containsAll([
      'Seul un administrateur peut valider un devis.',
      'Des lignes n\'ont pas de prix.',
      'Le métré doit être validé (et à jour) avant le devis.',
    ]));
    s.editQuote(p, q, () {
      q.lines.single
        ..unitPriceCents = 4500
        ..priceMissing = false;
    });
    p.metreValidation = buildValidation(p, userId: 'admin', userName: 'Admin');
    expect(s.validationProblems(p, q, isAdmin: true), isEmpty);

    s.validateQuote(p, q, userId: 'admin');
    expect(q.status, QuoteStatus.validated);
    expect(q.metreFingerprint, metreFingerprint(p));
    final frozen = quoteTotals(p, q).ttc;
    s.mutate(() => p.rooms.first.walls.first.length = 6, touch: p, room: p.rooms.first);
    expect(quoteTotals(p, q).ttc, frozen, reason: 'devis validé figé');

    final v2 = s.newVersion(p, q);
    expect(q.status, QuoteStatus.superseded);
    expect(v2.versionNo, 2);
    expect(v2.estimateId, q.estimateId);
    expect(v2.status, QuoteStatus.draft);
    expect(quoteTotals(p, v2).ttc, isNot(frozen), reason: 'la nouvelle version suit le métré');
  });

  test('Devis en euros : conversion au taux saisi, retour au dirham', () async {
    final (s, p) = await _setup();
    final q = s.createQuote(p);
    s.addLineFromWorkItem(p, q, WorkItem(id: 'w', name: 'Peinture', unit: 'm2', base: QuantityBase.floor, salePriceCents: 10850));
    s.setCurrency(p, q, 'EUR', rateE4: 108500, rateDate: DateTime(2026, 11, 1), rateSource: 'Bank Al-Maghrib');
    expect(q.lines.single.unitPriceCents, 1000); // 108,50 MAD = 10,00 €
    final server = quoteToServer(p, q);
    expect(server['exchange_rate_e4'], 108500);
    expect(server['exchange_rate_date'], '2026-11-01');
    s.setCurrency(p, q, 'MAD');
    expect(q.lines.single.unitPriceCents, 10850);
    expect(quoteToServer(p, q)['exchange_rate_e4'], isNull);
  });

  test('Reprise des devis Qiyas : envoyés conservés en local, brouillons sans numéro local', () {
    final data = AppData.fromJson({
      'company': {'vat': 20},
      'projects': [
        {
          'id': 'p',
          'quotes': [
            {'id': 'q1', 'num': 'DV-2026-0003', 'status': 'sent', 'remise': 5, 'acompte': 40, 'lines': [
              {'id': 'l', 'label': 'Peinture', 'pu': 4500, 'qty': 10, 'manual': true, 'base': 'free'},
            ]},
            {'id': 'q2', 'num': 'DV-2026-0004', 'status': 'draft', 'lines': []},
          ],
        },
      ],
    });
    final q1 = data.projects.single.quotes[0];
    final q2 = data.projects.single.quotes[1];
    expect(q1.legacy, isTrue);
    expect(q1.number, 'DV-2026-0003');
    expect(q1.discountBp, 500);
    expect(q1.depositBp, 4000);
    expect(q1.lines.single.vatRateBp, 2000);
    expect(q2.legacy, isFalse);
    expect(q2.number, isNull);
  });
}
