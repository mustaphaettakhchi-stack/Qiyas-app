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
import 'package:lamaalam/ui/screens/project_screen.dart';
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
    await tester.scrollUntilVisible(find.text('Ajouter'), 200, scrollable: find.byType(Scrollable).last);
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
}
