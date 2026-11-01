import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/app.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/domain/models.dart';
import 'package:lamaalam/session/api_client.dart';
import 'package:lamaalam/session/auth_service.dart';
import 'package:lamaalam/session/session_controller.dart';
import 'package:lamaalam/session/session_store.dart';
import 'package:lamaalam/sync/sync_engine.dart';
import 'package:lamaalam/ui/home_shell.dart';
import 'package:lamaalam/ui/screens/clients_screen.dart';
import 'package:lamaalam/ui/screens/dashboard_screen.dart';
import 'package:lamaalam/ui/screens/library_screen.dart';
import 'package:lamaalam/ui/screens/metre_screen.dart';
import 'package:lamaalam/ui/screens/plan_screen.dart';
import 'package:lamaalam/ui/screens/project_screen.dart';
import 'package:lamaalam/ui/screens/quote_screen.dart';
import 'package:lamaalam/ui/screens/room_screen.dart';
import 'package:lamaalam/ui/screens/sync_screen.dart';
import 'package:provider/provider.dart';

class _MemoryStore extends LocalStore {
  AppData? saved;
  @override
  Future<AppData?> load() async => saved;
  @override
  Future<void> save(AppData data) async => saved = data;
}

Future<(AppState, Widget Function(Widget))> _setup() async {
  final state = AppState(store: _MemoryStore());
  await state.init();
  final store = MemorySessionStore();
  final api = ApiClient(store: store);
  final session = SessionController(api: api, auth: AuthService(api), store: store);
  final engine = SyncEngine(state: state, session: session, debounce: const Duration(days: 1));
  Widget wrap(Widget home) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: session),
          ChangeNotifierProvider.value(value: engine),
        ],
        child: MaterialApp(theme: lamaalamTheme(), home: home),
      );
  return (state, wrap);
}

void main() {
  // Petit écran de téléphone (360 × 740 points) : les débordements font échouer le test.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2220);
    view.devicePixelRatio = 3;
  });

  testWidgets('Navigation principale et liste des clients', (tester) async {
    final (state, wrap) = await _setup();
    state.createClient(name: 'M. Benali');
    await tester.pumpWidget(wrap(const HomeShell()));
    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();
    expect(find.text('M. Benali'), findsOneWidget);
    expect(find.text('Sur ce téléphone'), findsWidgets); // non connecté : pas de faux « Synchronisé »
  });

  testWidgets('Fiche projet : client, nature des travaux, photos soumises au consentement', (tester) async {
    final (state, wrap) = await _setup();
    final c = state.createClient(name: 'M. Benali');
    final p = state.createProject(clientId: c.id);
    await tester.pumpWidget(wrap(ProjectScreen(projectId: p.id)));
    await tester.pumpAndSettle();
    expect(find.text('M. Benali'), findsOneWidget);
    expect(find.text('Rénovation'), findsOneWidget);
    expect(find.text('Référence attribuée à la première synchronisation'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Ajouter'),
      200,
      scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first,
    );
    await tester.tap(find.text('Ajouter'));
    await tester.pump();
    expect(find.textContaining('consentement'), findsOneWidget);
  });

  testWidgets('Fiche client et consentement', (tester) async {
    final (state, wrap) = await _setup();
    final c = state.createClient(name: 'Riad Zitoun');
    await tester.pumpWidget(wrap(ClientScreen(clientId: c.id)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Consentement du client'), 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Consentement du client'));
    await tester.pumpAndSettle();
    expect(c.hasConsent, isTrue);
    expect(c.consentTextVersion, Client.currentConsentVersion);
  });

  testWidgets('Écran de synchronisation avec un conflit', (tester) async {
    final (state, wrap) = await _setup();
    final c = state.createClient(name: 'M. Benali');
    state.data.conflicts.add(SyncConflict(
      entity: 'clients',
      id: c.id,
      reason: 'Modifié à la fois sur ce téléphone et sur le serveur.',
      server: {
        'version': 2,
        'deleted': false,
        'data': {...c.toServer(), 'display_name': 'M. Benali Karim'},
      },
    ));
    await tester.pumpWidget(wrap(const SyncScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Serveur : M. Benali Karim'), findsOneWidget);
    expect(find.text('Garder la mienne'), findsOneWidget);
  });

  testWidgets('Pièce : rectangle, passage mur par mur, alerte de fermeture', (tester) async {
    final (state, wrap) = await _setup();
    final p = state.createProject();
    final r = state.addRoom(p);
    await tester.pumpWidget(wrap(RoomScreen(projectId: p.id, roomId: r.id)));
    await tester.pumpAndSettle();
    expect(find.text('Longueur (m) · à vérifier'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('cote(s) à la valeur standard'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('cote(s) à la valeur standard'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mur par mur'), -300, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.text('Mur par mur'));
    await tester.pumpAndSettle();
    expect(find.text('Mur 4'), findsOneWidget);

    // Cotes incohérentes : 5 / 4 / 5,03 / 4.
    state.mutate(() {
      for (final (i, l) in [5.0, 4.0, 5.03, 4.0].indexed) {
        r.walls[i]
          ..length = l
          ..lengthSource = MeasureSource.manual;
      }
    }, touch: p, room: r);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('ne se referment pas'), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('ne se referment pas'), findsOneWidget);
  });

  testWidgets('Plan : pièce en L et pièce rectangulaire', (tester) async {
    final (state, wrap) = await _setup();
    final p = state.createProject();
    final l = state.addRoom(p);
    state.mutate(() {
      l.walls = [
        for (final (i, (len, a)) in [(6.0, 90.0), (2.0, 90.0), (2.0, 270.0), (2.0, 90.0), (4.0, 90.0), (4.0, 90.0)].indexed)
          Wall(id: 'w$i', length: len, angle: a),
      ];
      l.openings = [Opening(id: 'd', type: OpeningType.door, wallIndex: 4, width: 0.9, height: 2.1)];
    }, touch: p, room: l);
    state.addRoom(p);
    await tester.pumpWidget(wrap(PlanScreen(projectId: p.id)));
    await tester.pumpAndSettle();
    expect(find.text('Plan'), findsOneWidget);
    expect(l.planX, isNotNull);
  });

  testWidgets('Bibliothèque vide puis fiche ouvrage en consultation seule', (tester) async {
    final (state, wrap) = await _setup();
    await tester.pumpWidget(wrap(const LibraryScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Aucun élément.'), findsOneWidget); // production : démarre vide
    expect(find.textContaining('consultation seule'), findsOneWidget); // non administrateur
    state.addTemplate('Électricité simple');
    await tester.pumpAndSettle();
    expect(find.text('Prix à renseigner'), findsWidgets);
    final w = state.workItems.first;
    await tester.pumpWidget(wrap(WorkItemScreen(id: w.id)));
    await tester.pumpAndSettle();
    expect(find.text('Taux de perte'), findsOneWidget);
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Désignation')).enabled, isFalse);
  });

  testWidgets('Métré par lot avec comptages et bouton de validation', (tester) async {
    final (state, wrap) = await _setup();
    final p = state.createProject();
    final r = state.addRoom(p);
    state.mutate(() {
      for (final (i, l) in [5.0, 4.0, 5.0, 4.0].indexed) {
        r.walls[i]
          ..length = l
          ..lengthSource = MeasureSource.manual;
      }
      r.counts['prises'] = 6;
    }, touch: p, room: r);
    await tester.pumpWidget(wrap(MetreScreen(projectId: p.id)));
    await tester.pumpAndSettle();
    expect(find.text('Métré non validé.'), findsOneWidget);
    expect(find.textContaining('Valider le métré'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Prises'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Prises'), findsOneWidget);
  });

  testWidgets('Devis : lignes à prix direct et calculé, TVA, euros, totaux exacts', (tester) async {
    final (state, wrap) = await _setup();
    final p = state.createProject();
    final r = state.addRoom(p);
    state.mutate(() {
      for (final (i, l) in [5.0, 4.0, 5.0, 4.0].indexed) {
        r.walls[i].length = l;
      }
    }, touch: p, room: r);
    final q = state.createQuote(p);
    state.addLineFromWorkItem(p, q, WorkItem(id: 'w', name: 'Carrelage sol', unit: 'm2', base: QuantityBase.floor, salePriceCents: 25000));
    state.addLineFromWorkItem(p, q, WorkItem(id: 'x', name: 'Pose', unit: 'u', labourCostCents: 12000));
    state.setCurrency(p, q, 'EUR', rateE4: 108500, rateDate: DateTime(2026, 11, 1));
    await tester.pumpWidget(wrap(QuoteScreen(projectId: p.id, quoteId: q.id)));
    await tester.pumpAndSettle();
    expect(find.text('Brouillon v1'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Total TTC'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('€'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Valider le devis'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Valider le devis'), findsOneWidget);
  });

  testWidgets('Tableau de bord rempli : indicateurs, raccourcis, à faire', (tester) async {
    final (state, wrap) = await _setup();
    final c = state.createClient(name: 'Mme Alaoui Benjelloun El Idrissi');
    final p = state.createProject(clientId: c.id);
    state.mutate(() => p
      ..status = 'estimating'
      ..visitDate = DateTime.now(), touch: p, meta: true);
    final q = state.createQuote(p);
    state.addFreeLine(p, q);
    await tester.pumpWidget(wrap(const DashboardScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Prospects'), findsOneWidget);
    expect(find.text('Nouveau projet'), findsOneWidget);
    expect(find.text('Nouveau devis'), findsOneWidget);
    expect(find.textContaining('scan'), findsNothing); // pas de bouton sans action réelle (phase 2)
    await tester.scrollUntilVisible(find.textContaining('Visite aujourd\'hui'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Visite aujourd\'hui'), findsOneWidget);
  });
}
