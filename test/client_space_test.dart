import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
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
import 'package:lamaalam/ui/screens/client/client_home_screen.dart';
import 'package:provider/provider.dart';

import 'support/fake_http.dart';

class _MemoryStore extends LocalStore {
  AppData? saved;
  @override
  Future<AppData?> load() async => saved;
  @override
  Future<void> save(AppData data) async => saved = data;
}

Map<String, dynamic> _profile(List<String> roles) => {
  'id': 'u1',
  'organization_id': 'o1',
  'email': 'client@exemple.ma',
  'full_name': 'Mme Alaoui',
  'roles': roles,
  'totp_enabled': false,
};

const _pid = '0190f1e2-0000-7000-8000-000000000001';
const _project = {
  'id': _pid,
  'reference': 'PR-2026-0007',
  'name': 'Villa Malabata',
  'status': 'estimate_sent',
  'project_type': 'renovation',
  'site_address': '12 rue des Oliviers',
  'site_city': 'Tanger',
  'updated_at': '2026-11-02T08:00:00Z',
};

final _detail = {
  ..._project,
  'quotes': [
    {
      'id': 'q1',
      'reference': 'DV-2026-0012',
      'version_no': 1,
      'status': 'sent',
      'issue_date': '2026-11-01',
      'validity_days': 30,
      'currency': 'MAD',
      'total_ht_cents': 1000000,
      'total_ttc_cents': 1200000,
      'pdf_file_id': 'f1',
    },
  ],
  'photos': <Object>[],
  'timeline': [
    {'occurred_at': '2026-11-01T09:00:00Z', 'action': 'project.create', 'reference': 'PR-2026-0007'},
    {'occurred_at': '2026-11-02T08:00:00Z', 'action': 'estimate.send', 'reference': 'DV-2026-0012'},
  ],
};

Future<(SessionController, FakeAdapter, Widget)> _app(List<String> roles) async {
  final state = AppState(store: _MemoryStore());
  await state.init();
  final store = MemorySessionStore();
  await store.write(SessionKeys.profile, jsonEncode(_profile(roles)));
  await store.write(SessionKeys.refreshToken, 'r0');
  await store.write(SessionKeys.apiUrl, 'https://api.test');
  final messages = <Map<String, dynamic>>[];
  final http = FakeAdapter((r) {
    final path = r.path.replaceFirst('https://api.test/api/v1', '');
    return switch ((r.method, path)) {
      ('POST', '/auth/refresh') => (200, {'access_token': 'a1', 'refresh_token': 'r1'}),
      ('GET', '/auth/me') => (200, _profile(roles)),
      ('GET', '/client/projects') => (200, [_project]),
      ('GET', '/client/projects/$_pid') => (200, _detail),
      ('GET', '/client/projects/$_pid/messages') => (200, messages),
      ('POST', '/client/projects/$_pid/messages') => (
        201,
        () {
          final m = {
            'id': 'm${messages.length}',
            'author_name': 'Mme Alaoui',
            'from_client': true,
            'body': (r.data as Map)['body'],
            'created_at': '2026-11-02T10:00:00Z',
          };
          messages.add(m);
          return m;
        }(),
      ),
      // Un compte client n'a jamais accès à la synchronisation.
      ('GET', _) when path.startsWith('/sync') => (403, {'detail': 'Action réservée à un autre profil.'}),
      _ => (404, {'detail': 'Élément introuvable.'}),
    };
  });
  final api = ApiClient(store: store, dio: Dio()..httpClientAdapter = http);
  final session = SessionController(api: api, auth: AuthService(api), store: store);
  final engine = SyncEngine(state: state, session: session, debounce: const Duration(days: 1));
  await session.restore();
  final app = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: state),
      ChangeNotifierProvider.value(value: session),
      ChangeNotifierProvider.value(value: engine),
    ],
    child: const LamaalamApp(),
  );
  return (session, http, app);
}

void main() {
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 2220);
    view.devicePixelRatio = 3;
  });

  testWidgets('Compte client : son espace en lecture seule, jamais l\'application de l\'équipe', (tester) async {
    late FakeAdapter http;
    late Widget app;
    await tester.runAsync(() async => (_, http, app) = await _app(['client']));
    await tester.pumpWidget(app);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.byType(ClientHomeScreen), findsOneWidget);
    expect(find.text('Bibliothèque'), findsNothing);
    expect(find.text('Villa Malabata'), findsOneWidget);
    expect(http.requests.where((r) => r.path.contains('/sync/')), isEmpty);

    await tester.tap(find.text('Villa Malabata'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 000,00 MAD TTC'), findsOneWidget);
    expect(find.textContaining('En attente de votre réponse'), findsOneWidget);
    expect(find.textContaining('Devis envoyé · DV-2026-0012'), findsOneWidget);
    expect(find.textContaining('Aucune photo partagée'), findsOneWidget);
    expect(find.textContaining('signature électronique'), findsOneWidget);
    for (final hidden in ['Marge', 'marge', 'Déboursé', 'Frais']) {
      expect(find.textContaining(hidden), findsNothing);
    }

    await tester.tap(find.text('Messages'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Aucun message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Quand commencez-vous ?');
    await tester.tap(find.byTooltip('Envoyer'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Quand commencez-vous ?'), findsOneWidget);
    final sent = http.requests.lastWhere((r) => r.method == 'POST');
    expect(sent.path, endsWith('/client/projects/$_pid/messages'));
  });

  testWidgets('Compte de l\'équipe : application complète', (tester) async {
    late Widget app;
    await tester.runAsync(() async => (_, _, app) = await _app(['collaborator']));
    await tester.pumpWidget(app);
    await tester.pump();
    expect(find.byType(ClientHomeScreen), findsNothing);
    expect(find.text('Bibliothèque'), findsOneWidget);
    // Laisse s'éteindre les minuteries de l'interface (indicateurs, synchronisation différée).
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  group('Fichiers', () {
    late FakeAdapter http;
    late ApiClient api;

    setUp(() async {
      http = FakeAdapter((_) => (500, null));
      api = ApiClient(store: MemorySessionStore(), dio: Dio()..httpClientAdapter = http);
      await api.setBaseUrl('https://api.test');
      await api.saveTokens({'access_token': 'a1', 'refresh_token': 'r1'});
    });

    test('Lien signé : téléchargé sans jeton, sur ce serveur uniquement', () async {
      http.handler = (_) => (200, [1, 2, 3]);
      const link = '/api/v1/files/download/0190f1e2-0000-7000-8000-00000000000f?exp=1&uid=u&org=o&v=client&sig=ab12';
      final bytes = await api.download(link);
      expect(bytes, Uint8List.fromList(utf8.encode('[1,2,3]')));
      expect(http.requests.single.uri.toString(), 'https://api.test$link');
      expect(http.requests.single.headers['Authorization'], isNull);
      for (final bad in ['@evil.example/x', '//evil.example/x', '/api/v1/sync/pull', 'https://evil.example/api/v1/files/download/x?a=1']) {
        await expectLater(api.download(bad), throwsA(isA<ApiException>()), reason: bad);
      }
      expect(http.requests, hasLength(1));
    });

    test('Envoi de fichier rejoué après renouvellement de session avec un formulaire neuf', () async {
      var calls = 0;
      http.handler = (r) {
        if (r.path.endsWith('/auth/refresh')) return (200, {'access_token': 'a2', 'refresh_token': 'r2'});
        calls++;
        return calls == 1 ? (401, {'detail': 'Session expirée.'}) : (201, {'ok': true});
      };
      await api.upload(
        '/files',
        fields: {'project_id': 'p', 'kind': 'quote_pdf'},
        bytes: Uint8List.fromList([37, 80, 68, 70]),
        filename: 'devis.pdf',
      );
      final uploads = http.requests.where((r) => r.path.endsWith('/files')).toList();
      expect(uploads, hasLength(2));
      expect(identical(uploads[0].data, uploads[1].data), isFalse);
      final form = uploads[1].data as FormData;
      expect(Map.fromEntries(form.fields), {'project_id': 'p', 'kind': 'quote_pdf'});
      expect(form.files.single.value.filename, 'devis.pdf');
      expect(uploads[1].headers['Authorization'], 'Bearer a2');
    });
  });

  test('PDF à publier : seulement un devis envoyé, synchronisé et numéroté', () {
    Quote q() => Quote(id: 'q', date: DateTime(2026, 11, 1), status: QuoteStatus.sent, number: 'DV-2026-0001', clientPdfPending: true)
      ..serverVersion = 2
      ..dirty = false;
    expect(SyncEngine.pdfPublishable(q()), isTrue);
    expect(SyncEngine.pdfPublishable(q()..dirty = true), isFalse);
    expect(SyncEngine.pdfPublishable(q()..number = null), isFalse);
    expect(SyncEngine.pdfPublishable(q()..clientPdfPending = false), isFalse);
    expect(SyncEngine.pdfPublishable(q()..status = QuoteStatus.superseded), isFalse);
    expect(SyncEngine.pdfPublishable(q()..syncError = 'refusé'), isFalse);
    // Le marqueur survit à l'enregistrement local.
    expect(Quote.fromJson(q().toJson()).clientPdfPending, isTrue);
  });
}
