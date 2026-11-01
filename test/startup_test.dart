import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/data/templates.dart';
import 'package:lamaalam/domain/models.dart';

/// Stockage en mémoire : aucun fichier, aucun accès au système.
class _MemoryStore extends LocalStore {
  AppData? saved;

  @override
  Future<AppData?> load() async => saved;

  @override
  Future<void> save(AppData data) async => saved = data;
}

void main() {
  test('Premier lancement : aucune donnée de démonstration ni prix pré-rempli', () async {
    final state = AppState(store: _MemoryStore());
    await state.init();
    expect(state.data.projects, isEmpty);
    expect(state.data.workItems, isEmpty);
    expect(state.data.company.name, isEmpty);
  });

  test('Les modèles ajoutent des ouvrages sans prix ni taux de perte', () async {
    final state = AppState(store: _MemoryStore());
    await state.init();
    for (final trade in kPriceTemplates.keys) {
      state.addTemplate(trade);
    }
    expect(state.data.workItems, isNotEmpty);
    expect(state.data.workItems.every((w) => w.salePriceCents == null && w.wasteRateBp == 0), isTrue);
    // Une ligne de devis créée depuis un ouvrage sans prix est signalée et bloque l'envoi.
    final line = lineFrom(state.data.workItems.first, 'l');
    expect(line.priceMissing, isTrue);
  });

  test('Reprise Qiyas : le nom saisi devient une fiche client, sans doublon', () async {
    final store = _MemoryStore()
      ..saved = AppData.fromJson({
        'company': <String, dynamic>{},
        'projects': [
          {'id': '0190d6a2-0000-7000-8000-000000000001', 'client': 'M. Benali', 'phone': '0661000000', 'city': 'Tanger'},
          {'id': '0190d6a2-0000-7000-8000-000000000002', 'client': 'M. Benali', 'phone': '0661000000', 'city': 'Tanger'},
          {'id': '0190d6a2-0000-7000-8000-000000000003', 'client': '', 'city': 'Tanger'},
        ],
      });
    final state = AppState(store: store);
    await state.init();
    expect(state.data.clients, hasLength(1));
    expect(state.data.clients.single.displayName, 'M. Benali');
    expect(state.data.projects.where((p) => p.clientId == state.data.clients.single.id), hasLength(2));
    expect(state.data.projects.every((p) => p.dirty), isTrue);
    expect(state.clientName(state.data.projects.last), 'Client à renseigner');
  });

  test('Les modifications de pièces ne marquent pas la fiche projet comme à synchroniser', () async {
    final state = AppState(store: _MemoryStore());
    await state.init();
    final p = state.createProject();
    p.dirty = false;
    state.addRoom(p);
    expect(p.dirty, isFalse);
    state.mutate(() => p.notes = 'Accès par la cour', touch: p, meta: true);
    expect(p.dirty, isTrue);
  });

  testWidgets('Le logo LAMAALAM est embarqué dans l\'application', (tester) async {
    final bytes = await rootBundle.load('assets/branding/logo_lamaalam_corrige_512.png');
    expect(bytes.lengthInBytes, greaterThan(10000));
  });
}
