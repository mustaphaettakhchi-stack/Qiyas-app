import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/data/templates.dart';
import 'package:lamaalam/domain/models.dart';
import 'package:lamaalam/services/sync_service.dart';

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
    final state = AppState(store: _MemoryStore(), sync: LocalOnlySyncService());
    await state.init();
    expect(state.data.projects, isEmpty);
    expect(state.data.prestations, isEmpty);
    expect(state.data.company.name, isEmpty);
  });

  test('Les grilles modèles ajoutent des prestations à prix nul', () async {
    final state = AppState(store: _MemoryStore(), sync: LocalOnlySyncService());
    await state.init();
    for (final trade in kPriceTemplates.keys) {
      state.addTemplate(trade);
    }
    expect(state.data.prestations, isNotEmpty);
    expect(state.data.prestations.every((p) => p.unitPriceCents == 0), isTrue);
  });

  test('Sans serveur, aucun projet n\'est déclaré synchronisé', () async {
    final data = AppData(company: Company(), prestations: [], projects: [Project(id: 'p')]);
    expect(await LocalOnlySyncService().push(data), isEmpty);
  });

  testWidgets('Le logo LAMAALAM est embarqué dans l\'application', (tester) async {
    final bytes = await rootBundle.load('assets/branding/logo_lamaalam_sans_telephone_512.png');
    expect(bytes.lengthInBytes, greaterThan(10000));
  });
}
