import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/core/config.dart';
import 'package:lamaalam/session/api_client.dart';
import 'package:lamaalam/session/auth_service.dart';
import 'package:lamaalam/session/session_controller.dart';
import 'package:lamaalam/session/session_store.dart';

import 'support/fake_http.dart';

const _profile = {
  'id': 'u1',
  'organization_id': 'o1',
  'email': 'karim@exemple.ma',
  'full_name': 'Karim',
  'roles': ['admin'],
  'totp_enabled': true,
  'locale': 'fr',
};

Map<String, String> _tokens(String n) => {'access_token': 'acces-$n', 'refresh_token': 'renouv-$n'};

void main() {
  group('Adresse du serveur', () {
    test('HTTPS accepté et normalisé', () {
      expect(normalizeApiUrl(' https://api.exemple.ma/ ', allowHttp: false), 'https://api.exemple.ma');
    });
    test('HTTP refusé hors développement', () {
      expect(normalizeApiUrl('http://api.exemple.ma', allowHttp: false), isNull);
      expect(normalizeApiUrl('http://10.0.2.2:8000', allowHttp: true), 'http://10.0.2.2:8000');
    });
    test('Adresse invalide refusée', () {
      expect(normalizeApiUrl('api.exemple.ma', allowHttp: false), isNull);
      expect(normalizeApiUrl('', allowHttp: false), isNull);
    });
  });

  test('Jeton extrait d\'un lien d\'invitation ou collé seul', () {
    const t = 'AbCdEfGhIjKlMnOpQrStUvWxYz012345-_';
    expect(invitationTokenFrom('https://api.exemple.ma/invitation#$t'), t);
    expect(invitationTokenFrom('  $t '), t);
    expect(invitationTokenFrom('https://api.exemple.ma/invitation#court'), isNull);
    expect(invitationTokenFrom('<script>'), isNull);
  });

  group('Client API', () {
    late MemorySessionStore store;
    late FakeAdapter http;
    late ApiClient api;

    setUp(() async {
      store = MemorySessionStore();
      http = FakeAdapter((_) => (500, null));
      api = ApiClient(store: store, dio: Dio()..httpClientAdapter = http);
      await api.setBaseUrl('https://api.test');
    });

    test('Jeton expiré : renouvellement puis nouvelle tentative', () async {
      await api.saveTokens(_tokens('1'));
      http.handler = (r) {
        if (r.path.endsWith('/auth/refresh')) return (200, _tokens('2'));
        final auth = r.headers['Authorization'];
        return auth == 'Bearer acces-2' ? (200, _profile) : (401, {'detail': 'Session expirée. Reconnectez-vous.'});
      };
      final me = await api.get('/auth/me') as Map;
      expect(me['email'], 'karim@exemple.ma');
      expect(await store.read(SessionKeys.refreshToken), 'renouv-2');
    });

    test('Session refusée par le serveur : jetons effacés et alerte de révocation', () async {
      await api.saveTokens(_tokens('1'));
      var revoked = false;
      api.onSessionRevoked = () => revoked = true;
      http.handler = (r) => (401, {'detail': 'Session expirée. Reconnectez-vous.'});
      await expectLater(api.get('/auth/me'), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));
      expect(revoked, isTrue);
      expect(await store.read(SessionKeys.refreshToken), isNull);
    });

    test('Serveur injoignable : erreur réseau explicite', () async {
      http.offline = true;
      await expectLater(
        api.postPublic('/auth/login', {}),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'réseau', isTrue)),
      );
    });

    test('Message d\'erreur du serveur transmis tel quel', () async {
      http.handler = (_) => (401, {'detail': 'Adresse e-mail ou mot de passe incorrect.'});
      await expectLater(
        AuthService(api).login('a@b.ma', 'x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Adresse e-mail ou mot de passe incorrect.')),
      );
    });

    test('Connexion : les trois issues possibles', () async {
      final auth = AuthService(api);
      http.handler = (_) => (200, {'tokens': null, 'mfa_required': true, 'mfa_setup_required': false, 'mfa_token': 'm'});
      expect(await auth.login('a@b.ma', 'x'), isA<LoginNeedsCode>());
      http.handler = (_) => (200, {'tokens': null, 'mfa_required': false, 'mfa_setup_required': true, 'mfa_token': 'm'});
      expect(await auth.login('a@b.ma', 'x'), isA<LoginNeedsMfaSetup>());
      http.handler = (_) => (200, {'tokens': _tokens('9'), 'mfa_required': false, 'mfa_setup_required': false});
      expect(await auth.login('a@b.ma', 'x'), isA<LoginDone>());
      expect(await store.read(SessionKeys.refreshToken), 'renouv-9');
    });
  });

  group('Session au démarrage', () {
    late MemorySessionStore store;
    late FakeAdapter http;
    late SessionController session;

    setUp(() async {
      store = MemorySessionStore();
      await store.write(SessionKeys.apiUrl, 'https://api.test');
      await store.write(SessionKeys.refreshToken, 'renouv-1');
      await store.write(SessionKeys.profile, jsonEncode(_profile));
      http = FakeAdapter((_) => (500, null));
      final api = ApiClient(store: store, dio: Dio()..httpClientAdapter = http);
      session = SessionController(api: api, auth: AuthService(api), store: store);
    });

    test('Hors connexion : l\'utilisateur garde l\'accès à ses données', () async {
      http.offline = true;
      await session.restore();
      expect(session.isAuthenticated, isTrue);
      expect(session.verifiedOnline, isFalse);
    });

    test('Session révoquée côté serveur : déconnexion au retour du réseau', () async {
      http.handler = (_) => (401, {'detail': 'Session expirée. Reconnectez-vous.'});
      await session.restore();
      expect(session.isAuthenticated, isFalse);
      expect(await store.read(SessionKeys.profile), isNull);
      expect(await store.read(SessionKeys.refreshToken), isNull);
    });

    test('Session valide : profil rafraîchi depuis le serveur', () async {
      http.handler = (r) => r.path.endsWith('/auth/refresh') ? (200, _tokens('2')) : (200, {..._profile, 'full_name': 'Karim B.'});
      await session.restore();
      expect(session.verifiedOnline, isTrue);
      expect(session.user!.fullName, 'Karim B.');
    });

    test('Sans session mémorisée : écran de connexion', () async {
      await store.delete(SessionKeys.refreshToken);
      await session.restore();
      expect(session.isAuthenticated, isFalse);
      expect(http.requests, isEmpty);
    });

    test('Le mode démonstration n\'est pas compilé par défaut', () {
      expect(AppConfig.demoMode, isFalse);
    });
  });
}
