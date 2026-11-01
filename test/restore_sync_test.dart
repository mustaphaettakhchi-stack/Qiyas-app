import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/domain/models.dart';
import 'package:lamaalam/session/api_client.dart';
import 'package:lamaalam/session/auth_service.dart';
import 'package:lamaalam/session/session_controller.dart';
import 'package:lamaalam/session/session_store.dart';
import 'package:lamaalam/sync/sync_engine.dart';

import 'support/fake_http.dart';

class _MemoryStore extends LocalStore {
  AppData? saved;
  @override
  Future<AppData?> load() async => saved;
  @override
  Future<void> save(AppData data) async => saved = data;
}

const _profile = {
  'id': 'u1',
  'organization_id': 'o1',
  'email': 'collab@exemple.ma',
  'full_name': 'Collaborateur',
  'roles': ['collaborator'],
  'totp_enabled': true,
};

void main() {
  test('Serveur restauré : synchronisation suspendue, puis reprise sans rien perdre', () async {
    final state = AppState(store: _MemoryStore());
    await state.init();
    // Ce téléphone a déjà synchronisé un client (version 3) et un projet créé APRÈS la sauvegarde.
    final c = state.createClient(name: 'Mme Alaoui');
    final p = state.createProject(clientId: c.id);
    for (final x in <Syncable>[c, p]) {
      x
        ..serverVersion = 3
        ..dirty = false;
    }
    state.data
      ..syncCursor = 500
      ..lastSyncAt = DateTime(2026, 11, 1)
      ..syncAccount = 'u1';

    final pushes = <Map<String, dynamic>>[];
    final http = FakeAdapter((r) {
      final path = r.path.replaceFirst('https://api.test/api/v1', '');
      if (path == '/auth/refresh') return (200, {'access_token': 'a', 'refresh_token': 'r'});
      if (path == '/auth/me') return (200, _profile);
      if (path == '/sync/epoch') return (200, {'epoch': 'restauration-1'});
      if (path == '/sync/push') {
        final changes = [for (final ch in (r.data as Map)['changes'] as List) Map<String, dynamic>.from(ch as Map)];
        pushes.addAll(changes);
        return (200, {
          'results': [
            for (final ch in changes)
              {
                'entity': ch['entity'],
                'id': ch['id'],
                'status': 'applied',
                'record': {
                  'entity': ch['entity'],
                  'id': ch['id'],
                  'version': 1,
                  'deleted': false,
                  'reference': 'LMA-2026-0142',
                  'updated_at': '2026-11-02T10:00:00Z',
                  'sync_seq': 1000000001,
                  'data': ch['data'],
                },
              },
          ],
        });
      }
      if (path.startsWith('/sync/pull')) {
        // Le serveur restauré connaît le client, dans une version plus ancienne, mais pas le projet.
        return (200, {
          'records': [
            {
              'entity': 'clients',
              'id': c.id,
              'version': 2,
              'deleted': false,
              'sync_seq': 7,
              'updated_at': '2026-10-31T10:00:00Z',
              'data': {'display_name': 'Mme Alaoui (ancienne)', 'phone': '', 'city': 'Tanger'},
            },
          ],
          'cursor': 7,
          'has_more': false,
          'epoch': 'restauration-1',
        });
      }
      return (404, {'detail': 'Élément introuvable.'});
    });
    final store = MemorySessionStore();
    await store.write(SessionKeys.profile, jsonEncode(_profile));
    await store.write(SessionKeys.refreshToken, 'r0');
    await store.write(SessionKeys.apiUrl, 'https://api.test');
    final api = ApiClient(store: store, dio: Dio()..httpClientAdapter = http);
    final session = SessionController(api: api, auth: AuthService(api), store: store);
    final engine = SyncEngine(state: state, session: session, debounce: const Duration(days: 1));
    await session.restore();
    await engine.syncNow();

    // 1. Restauration détectée AVANT tout envoi : rien n'est envoyé ni reçu.
    expect(state.data.restoredEpoch, 'restauration-1');
    expect(engine.lastError, SyncEngine.restoreMessage);
    expect(http.requests.where((r) => r.path.contains('/sync/push') || r.path.contains('/sync/pull')), isEmpty);
    await engine.syncNow();
    expect(http.requests.where((r) => r.path.contains('/sync/push')), isEmpty, reason: 'reste suspendu');

    // 2. Reprise décidée par l'utilisateur.
    await engine.resumeAfterRestore();
    expect(state.data.restoredEpoch, isNull);
    expect(state.data.syncEpoch, 'restauration-1');
    expect(state.data.fullResync, isFalse);
    // Version plus ancienne sur le serveur : conflit, la fiche du téléphone est intacte.
    expect(state.data.conflicts.map((x) => x.id), [c.id]);
    expect(c.displayName, 'Mme Alaoui');
    // Projet inconnu du serveur : renvoyé comme nouveau (sans version de départ).
    expect(engine.resent, 1);
    final sentProject = pushes.singleWhere((x) => x['entity'] == 'projects');
    expect(sentProject['id'], p.id);
    expect(sentProject['base_version'], isNull);
    expect(p.dirty, isFalse);
    expect(p.reference, 'LMA-2026-0142');
    // Le client en conflit n'est pas renvoyé tant que l'utilisateur n'a pas arbitré.
    expect(pushes.where((x) => x['entity'] == 'clients'), isEmpty);

    // 3. L'utilisateur garde sa version : elle part avec la version du serveur comme base.
    engine.keepMine(state.data.conflicts.single);
    await engine.syncNow();
    final sentClient = pushes.lastWhere((x) => x['entity'] == 'clients');
    expect(sentClient['base_version'], 2);
    expect((sentClient['data'] as Map)['display_name'], 'Mme Alaoui');
  });
}
