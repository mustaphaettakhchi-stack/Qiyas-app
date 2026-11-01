// Test de bout en bout contre un vrai serveur LAMAALAM.
// Lancé par tool/integration_test.sh ; ignoré si LAMAALAM_IT_API_URL n'est pas défini.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/domain/models.dart';
import 'package:lamaalam/session/api_client.dart';
import 'package:lamaalam/session/auth_service.dart';
import 'package:lamaalam/session/session_controller.dart';
import 'package:lamaalam/session/session_store.dart';
import 'package:lamaalam/sync/sync_engine.dart';

class _MemoryStore extends LocalStore {
  AppData? saved;

  @override
  Future<AppData?> load() async => saved;

  @override
  Future<void> save(AppData data) async => saved = data;
}

// Partagé entre les deux tests (exécutés dans l'ordre).
String? _adminSecret;
String? _collabEmail;
String? _collabSecret;
const _collabPassword = 'Fontaine-cuivre-jasmin-port-24';

/// Code TOTP (RFC 6238, SHA-1, 6 chiffres, 30 s), comme une application d'authentification.
String totp(String base32Secret, {DateTime? at, int offsetSteps = 0}) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = '';
  for (final ch in base32Secret.replaceAll('=', '').toUpperCase().split('')) {
    bits += alphabet.indexOf(ch).toRadixString(2).padLeft(5, '0');
  }
  final key = Uint8List.fromList([
    for (var i = 0; i + 8 <= bits.length; i += 8) int.parse(bits.substring(i, i + 8), radix: 2),
  ]);
  final step = (at ?? DateTime.now()).millisecondsSinceEpoch ~/ 30000 + offsetSteps;
  final msg = ByteData(8)..setInt64(0, step);
  final h = Hmac(sha1, key).convert(msg.buffer.asUint8List()).bytes;
  final o = h.last & 0x0f;
  final bin = ((h[o] & 0x7f) << 24) | (h[o + 1] << 16) | (h[o + 2] << 8) | h[o + 3];
  return (bin % 1000000).toString().padLeft(6, '0');
}

void main() {
  final url = Platform.environment['LAMAALAM_IT_API_URL'];
  final email = Platform.environment['LAMAALAM_IT_ADMIN_EMAIL'] ?? '';
  final password = Platform.environment['LAMAALAM_IT_ADMIN_PASSWORD'] ?? '';
  final skip = url == null ? 'LAMAALAM_IT_API_URL non défini' : false;

  Future<SessionController> newSession(MemorySessionStore store) async {
    final api = ApiClient(store: store);
    await api.setBaseUrl(url!);
    final s = SessionController(api: api, auth: AuthService(api), store: store);
    await s.restore();
    return s;
  }

  test('Parcours complet : 2FA, équipe, invitation, déconnexion', () async {
    final store = MemorySessionStore();
    final session = await newSession(store);
    expect(session.isAuthenticated, isFalse);

    // 1. Mot de passe correct mais 2FA à configurer (administrateur créé en ligne de commande).
    final step = await session.auth.login(email, password);
    expect(step, isA<LoginNeedsMfaSetup>());
    final mfaToken = (step as LoginNeedsMfaSetup).mfaToken;

    // 2. Mise en place de la 2FA.
    final info = await session.auth.mfaSetup(mfaToken);
    expect(info.otpauthUri, startsWith('otpauth://totp/'));
    await expectLater(
      session.auth.mfaConfirm(mfaToken, '000000'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );
    final codes = await session.auth.mfaConfirm(mfaToken, totp(info.secret));
    _adminSecret = info.secret;
    expect(codes, hasLength(10));
    await session.completeLogin();
    expect(session.user!.isAdmin, isTrue);
    expect(session.user!.totpEnabled, isTrue);

    // 3. Administration de l'équipe.
    final users = await session.api.get('/users') as List;
    expect(users.map((u) => (u as Map)['email']), contains(email));
    final collabEmail = _collabEmail = 'collab-${DateTime.now().millisecondsSinceEpoch}@exemple.ma';
    final inv = await session.api.post('/invitations', {
      'email': collabEmail,
      'full_name': 'Collaborateur Test',
      'role': 'collaborator',
    }) as Map;
    final token = invitationTokenFrom(inv['invitation_url'] as String)!;

    // 4. Le collaborateur crée son compte, depuis un autre téléphone.
    final other = await newSession(MemorySessionStore());
    await expectLater(
      other.auth.acceptInvitation(token, 'motdepasse123'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 422)),
    );
    await other.auth.acceptInvitation(token, 'Escalier-citron-volet-bleu-71');
    expect(await other.auth.login(collabEmail, 'Escalier-citron-volet-bleu-71'), isA<LoginNeedsMfaSetup>());

    // 5. Un collaborateur ne peut pas administrer l'équipe (vérifié par le serveur).
    final collabStep = await other.auth.login(collabEmail, 'Escalier-citron-volet-bleu-71') as LoginNeedsMfaSetup;
    final collabInfo = await other.auth.mfaSetup(collabStep.mfaToken);
    await other.auth.mfaConfirm(collabStep.mfaToken, totp(collabInfo.secret));
    _collabSecret = collabInfo.secret;
    await other.completeLogin();
    await expectLater(
      other.api.get('/users'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
    );

    // 5 bis. Mot de passe oublié : lien créé par l'administrateur, usage unique.
    final collabId = ((await session.api.get('/users') as List)
        .map((u) => Map<String, dynamic>.from(u as Map))
        .firstWhere((u) => u['email'] == collabEmail))['id'];
    final reset = await session.api.post('/users/$collabId/password-reset') as Map;
    final resetUrl = reset['reset_url'] as String;
    expect(isPasswordResetLink(resetUrl), isTrue);
    await other.auth.acceptPasswordReset(invitationTokenFrom(resetUrl)!, 'Fontaine-cuivre-jasmin-port-24');
    expect(await other.auth.login(collabEmail, 'Fontaine-cuivre-jasmin-port-24'), isA<LoginNeedsCode>());
    await expectLater(
      other.api.get('/auth/me'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
    );

    // 6. Redémarrage de l'application : la session est retrouvée et vérifiée.
    final restarted = await newSession(store);
    expect(restarted.isAuthenticated, isTrue);
    expect(restarted.verifiedOnline, isTrue);

    // 7. Déconnexion : la session ne peut plus être utilisée.
    final refreshBefore = await store.read(SessionKeys.refreshToken);
    await restarted.logout();
    expect(restarted.isAuthenticated, isFalse);
    final replay = MemorySessionStore();
    await replay.write(SessionKeys.refreshToken, refreshBefore!);
    final replayApi = ApiClient(store: replay);
    await replayApi.setBaseUrl(url!);
    expect(await replayApi.refresh(), isFalse);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  /// Connexion complète ; le code TOTP du pas suivant est essayé si le code courant a déjà servi.
  Future<SessionController> loginPhone(String email, String password, String secret) async {
    final s = await newSession(MemorySessionStore());
    final step = await s.auth.login(email, password) as LoginNeedsCode;
    try {
      await s.auth.mfaVerify(step.mfaToken, code: totp(secret));
    } on ApiException {
      await s.auth.mfaVerify(step.mfaToken, code: totp(secret, offsetSteps: 1));
    }
    await s.completeLogin();
    return s;
  }

  Future<(AppState, SyncEngine)> phone(SessionController session) async {
    final state = AppState(store: _MemoryStore());
    await state.init();
    final engine = SyncEngine(state: state, session: session, debounce: const Duration(days: 1));
    return (state, engine);
  }

  test('Synchronisation entre deux téléphones : hors ligne, conflit, coupure, suppression', () async {
    final adminSession = await loginPhone(email, password, _adminSecret!);
    final collabSession = await loginPhone(_collabEmail!, _collabPassword, _collabSecret!);
    final (admin, adminSync) = await phone(adminSession);
    final (collab, collabSync) = await phone(collabSession);

    // 1. Le collaborateur crée un client et un projet ; rien n'est encore envoyé.
    final client = collab.createClient(name: 'M. Benali');
    collab.mutate(() => client.phone = '0661000000', client: client);
    final project = collab.createProject(clientId: client.id);
    collab.mutate(() => project.city = 'Tanger', touch: project, meta: true);
    expect(collab.pendingCount, 2);
    expect(project.reference, isNull);

    await collabSync.syncNow();
    expect(collabSync.phase, SyncPhase.idle, reason: collabSync.lastError);
    expect(collab.pendingCount, 0);
    expect(project.reference, matches(RegExp(r'^LMA-\d{4}-\d{4}$')));
    expect(project.managerId, collabSession.user!.id, reason: 'responsable attribué par le serveur');

    // 2. L'administrateur reçoit les deux fiches.
    await adminSync.syncNow();
    final adminProject = admin.project(project.id)!;
    expect(admin.clientName(adminProject), 'M. Benali');
    expect(adminProject.reference, project.reference);

    // 3. Modifications simultanées : conflit, jamais d'écrasement silencieux.
    admin.mutate(() => adminProject.notes = 'Accès par la cour', touch: adminProject, meta: true);
    collab.mutate(() => project.notes = 'Clés chez le voisin', touch: project, meta: true);
    await adminSync.syncNow();
    await collabSync.syncNow();
    expect(collab.data.conflicts, hasLength(1));
    expect(project.notes, 'Clés chez le voisin');

    // Le collaborateur garde sa version ; l'administrateur la reçoit.
    collabSync.keepMine(collab.data.conflicts.single);
    await collabSync.syncNow();
    expect(collab.data.conflicts, isEmpty);
    expect(collab.pendingCount, 0);
    expect(collab.rejectedCount, 0);
    await adminSync.syncNow();
    expect(adminProject.notes, 'Clés chez le voisin');

    // 4. Coupure réseau : la saisie reste sur le téléphone puis part au retour du réseau.
    final realUrl = collabSession.api.baseUrl!;
    await collabSession.api.setBaseUrl('http://127.0.0.1:9');
    collab.mutate(() => client.city = 'Tétouan', client: client);
    await collabSync.syncNow();
    expect(collabSync.phase, SyncPhase.offline);
    expect(collab.pendingCount, 1);
    await collabSession.api.setBaseUrl(realUrl);
    await collabSync.syncNow();
    expect(collab.pendingCount, 0);
    await adminSync.syncNow();
    expect(admin.client(client.id)!.city, 'Tétouan');

    // 5. Envoi refusé par le serveur : message affiché, pas de boucle d'envoi.
    collab.mutate(() => client.ice = '123', client: client);
    await collabSync.syncNow();
    expect(client.syncError, isNotNull);
    expect(collab.rejectedCount, 1);
    collab.mutate(() => client.ice = '', client: client);
    await collabSync.syncNow();
    expect(client.syncError, isNull);
    expect(collab.pendingCount, 0);

    // 6. Suppression par l'administrateur d'un projet qui a des pièces sur le téléphone du
    //    collaborateur : conflit plutôt que perte des pièces.
    collab.addRoom(project);
    admin.mutate(() => adminProject.deleted = true, touch: adminProject, meta: true);
    await adminSync.syncNow();
    expect(admin.data.projects.where((p) => p.id == project.id), isEmpty);
    await collabSync.syncNow();
    expect(collab.data.conflicts.single.reason, contains('pièces'));
    collabSync.keepMine(collab.data.conflicts.single);
    await collabSync.syncNow();
    await adminSync.syncNow();
    expect(admin.project(project.id), isNotNull, reason: 'projet restauré sur le serveur');

    // 7. Un projet sans données locales supprimé ailleurs disparaît simplement.
    final p2 = admin.createProject(clientId: client.id);
    await adminSync.syncNow();
    await collabSync.syncNow();
    expect(collab.project(p2.id), isNull, reason: 'projet de l\'administrateur, non confié au collaborateur');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
