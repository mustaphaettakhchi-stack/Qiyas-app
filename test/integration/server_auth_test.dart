// Test de bout en bout contre un vrai serveur LAMAALAM.
// Lancé par tool/integration_test.sh ; ignoré si LAMAALAM_IT_API_URL n'est pas défini.

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lamaalam/data/app_state.dart';
import 'package:lamaalam/data/local_store.dart';
import 'package:lamaalam/domain/calculations.dart';
import 'package:lamaalam/domain/metre.dart';
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
final Map<String, int> _usedSteps = {};

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
    _usedSteps[info.secret] = DateTime.now().millisecondsSinceEpoch ~/ 30000;
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
    _usedSteps[collabInfo.secret] = DateTime.now().millisecondsSinceEpoch ~/ 30000;
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

  /// Connexion complète. Le serveur refuse un code déjà utilisé (protection contre le rejeu) :
  /// on retient le dernier pas de 30 s utilisé pour chaque secret et on attend le suivant si besoin.
  Future<SessionController> loginPhone(String email, String password, String secret) async {
    final s = await newSession(MemorySessionStore());
    final step = await s.auth.login(email, password) as LoginNeedsCode;
    int now() => DateTime.now().millisecondsSinceEpoch ~/ 30000;
    var candidate = now() - 1;
    final last = _usedSteps[secret];
    if (last != null && candidate <= last) candidate = last + 1;
    while (candidate > now() + 1) {
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    await s.auth.mfaVerify(step.mfaToken, code: totp(secret, offsetSteps: candidate - now()));
    _usedSteps[secret] = candidate;
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

    // 5 bis. Pièce en L saisie mur par mur chez le collaborateur : reçue à l'identique.
    final room = collab.addRoom(project);
    collab.mutate(() {
      room
        ..name = 'Séjour'
        ..height = 2.5
        ..heightSource = MeasureSource.manual
        ..walls = [
          for (final (i, (l, a)) in [(6.0, 90.0), (2.0, 90.0), (2.0, 270.0), (2.0, 90.0), (4.0, 90.0), (4.0, 90.0)].indexed)
            Wall(id: 'w$i', length: l, angle: a),
        ]
        ..openings = [Opening(id: 'porte', type: OpeningType.door, wallIndex: 4, width: 0.9, height: 2.1)];
    }, touch: project, room: room);
    await collabSync.syncNow();
    expect(collab.pendingCount, 0, reason: collabSync.lastError);
    await adminSync.syncNow();
    final adminRoom = admin.project(project.id)!.rooms.single;
    expect(roomMeasures(adminRoom).floor, closeTo(20, 1e-9));
    expect(roomMeasures(adminRoom).walls, closeTo(48.11, 1e-9));
    expect(adminRoom.unverifiedCount, 0);

    // Modification simultanée d'une pièce : conflit ; le collaborateur garde la version du serveur.
    admin.mutate(() => adminRoom.name = 'Salon', touch: adminProject, room: adminRoom);
    collab.mutate(() => room.height = 2.6, touch: project, room: room);
    await adminSync.syncNow();
    await collabSync.syncNow();
    final roomConflict = collab.data.conflicts.singleWhere((c) => c.entity == 'rooms');
    collabSync.keepServer(roomConflict);
    final collabRoom = collab.project(project.id)!.rooms.single;
    expect(collabRoom.name, 'Salon');
    expect(collabRoom.height, 2.5);

    // Suppression d'une pièce par l'administrateur : elle disparaît chez le collaborateur.
    admin.deleteRoom(adminProject, adminRoom);
    await adminSync.syncNow();
    expect(admin.data.roomTombstones, isEmpty);
    await collabSync.syncNow();
    expect(collab.project(project.id)!.rooms, isEmpty);

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
    await collabSync.syncNow(); // la pièce refusée pendant la suppression repart après restauration
    await adminSync.syncNow();
    expect(admin.project(project.id)!.rooms, hasLength(1));
    expect(collab.rejectedCount, 0);

    // 7. Un projet sans données locales supprimé ailleurs disparaît simplement.
    final p2 = admin.createProject(clientId: client.id);
    await adminSync.syncNow();
    await collabSync.syncNow();
    expect(collab.project(p2.id), isNull, reason: 'projet de l\'administrateur, non confié au collaborateur');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('Bibliothèque partagée, comptages et validation du métré', () async {
    final adminSession = await loginPhone(email, password, _adminSecret!);
    final collabSession = await loginPhone(_collabEmail!, _collabPassword, _collabSecret!);
    final (admin, adminSync) = await phone(adminSession);
    final (collab, collabSync) = await phone(collabSession);

    // 1. L'administrateur crée fournisseur, matériau et ouvrage.
    final supplier = admin.addSupplier();
    admin.editLibrary(supplier, () => supplier.name = 'Céramique du Détroit');
    final material = admin.addMaterial();
    admin.editLibrary(material, () {
      material
        ..name = 'Carreau 60x60'
        ..unit = 'm2'
        ..supplierId = supplier.id
        ..purchasePriceCents = 12000
        ..salePriceCents = 18000
        ..priceNote = 'Devis n°12';
    });
    final work = admin.addWorkItem(name: 'Carrelage sol posé');
    admin.editLibrary(work, () {
      work
        ..category = 'floor'
        ..unit = 'm2'
        ..base = QuantityBase.floor
        ..wasteRateBp = 1000
        ..salePriceCents = 25000
        ..components = [{'material_id': material.id, 'quantity_per_unit': 1.0}];
    });
    await adminSync.syncNow();
    expect(adminSync.lastError, isNull);
    expect(work.serverVersion, isNotNull);

    // 2. Le collaborateur reçoit la bibliothèque, sans les prix d'achat.
    await collabSync.syncNow();
    final collabWork = collab.workItem(work.id)!;
    expect(collabWork.salePriceCents, 25000);
    expect(collabWork.wasteRateBp, 1000);
    expect(collab.material(material.id)!.purchasePriceCents, isNull);
    expect(collab.material(material.id)!.salePriceCents, 18000);

    // Une modification locale du collaborateur n'est jamais envoyée.
    collab.editLibrary(collabWork, () => collabWork.salePriceCents = 1);
    await collabSync.syncNow();
    await adminSync.syncNow();
    expect(admin.workItem(work.id)!.salePriceCents, 25000);

    // 3. Import CSV par l'administrateur, reçu par synchronisation.
    final imported = await adminSession.api.post('/library/import', {
      'kind': 'work_items',
      'csv': 'code;categorie;designation;description;unite;base;element_compte;perte_pct;prix_vente;main_oeuvre\n'
          'ELE-01;Électricité;Prise de courant;;u;comptage;prises;0;150;\n',
    }) as Map;
    expect(imported['created'], 1);
    await adminSync.syncNow();
    await collabSync.syncNow();
    final prise = collab.workItems.singleWhere((w) => w.code == 'ELE-01');
    expect(prise.base, QuantityBase.count);
    expect(prise.countKey, 'prises');

    // 4. Projet avec comptages, métré validé sur le téléphone du collaborateur.
    final client = collab.createClient(name: 'Mme Alaoui');
    final project = collab.createProject(clientId: client.id);
    final room = collab.addRoom(project);
    collab.mutate(() {
      room
        ..name = 'Salon'
        ..height = 2.7
        ..heightSource = MeasureSource.manual
        ..walls = [for (final (i, l) in [5.0, 4.0, 5.0, 4.0].indexed) Wall(id: 'w$i', length: l)]
        ..counts = {'prises': 6};
    }, touch: project, room: room);
    collab.mutate(() => project.metreValidation = buildValidation(project, userId: collabSession.user!.id, userName: 'Collaborateur Test'),
        touch: project, meta: true);
    await collabSync.syncNow();
    expect(collab.pendingCount, 0, reason: collabSync.lastError);

    // 5. L'administrateur reçoit le métré validé, identique (même empreinte après le serveur).
    await adminSync.syncNow();
    final adminProject = admin.project(project.id)!;
    expect(adminProject.rooms.single.counts, {'prises': 6.0});
    expect(metreState(adminProject), MetreState.validated);
    final quote = admin.createQuote(adminProject);
    admin.addLineFromWorkItem(adminProject, quote, admin.workItem(work.id)!);
    admin.addLineFromWorkItem(adminProject, quote, admin.workItems.singleWhere((w) => w.code == 'ELE-01'));
    expect(lineQuantity(adminProject, quote.lines[0]), 22); // 20 m² + 10 % de perte
    expect(lineQuantity(adminProject, quote.lines[1]), 6); // 6 prises comptées
    expect(quoteTotals(adminProject, quote).ht, 22 * 25000 + 6 * 15000);

    // Une cote modifiée ensuite rend le métré « à revalider » sur l'autre téléphone.
    collab.mutate(() => room.walls[0].length = 5.2, touch: project, room: room);
    await collabSync.syncNow();
    await adminSync.syncNow();
    expect(metreState(admin.project(project.id)!), MetreState.stale);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('Devis : brouillon du collaborateur, validation et numéro, figé, envoyé, accepté, nouvelle version', () async {
    final adminSession = await loginPhone(email, password, _adminSecret!);
    final collabSession = await loginPhone(_collabEmail!, _collabPassword, _collabSecret!);
    final (admin, adminSync) = await phone(adminSession);
    final (collab, collabSync) = await phone(collabSession);
    admin.data.company.ice = '001234567000089';
    collab.data.company.ice = '001234567000089';
    await adminSync.syncNow();
    await collabSync.syncNow();

    // 1. Le collaborateur relève, valide le métré et prépare un brouillon.
    final client = collab.createClient(name: 'محمد بنعلي');
    final project = collab.createProject(clientId: client.id);
    final room = collab.addRoom(project);
    collab.mutate(() {
      room
        ..heightSource = MeasureSource.manual
        ..walls = [for (final (i, l) in [5.0, 4.0, 5.0, 4.0].indexed) Wall(id: 'w$i', length: l)]
        ..counts = {'prises': 3};
    }, touch: project, room: room);
    collab.mutate(() => project.metreValidation = buildValidation(project, userId: collabSession.user!.id, userName: 'Collab'),
        touch: project, meta: true);
    final quote = collab.createQuote(project);
    final carrelage = collab.workItems.firstWhere((w) => w.base == QuantityBase.floor && w.salePriceCents != null);
    final prise = collab.workItems.firstWhere((w) => w.code == 'ELE-01');
    collab.addLineFromWorkItem(project, quote, carrelage);
    collab.addLineFromWorkItem(project, quote, prise);
    collab.editQuote(project, quote, () => quote.lines.last.vatRateBp = 1000);
    expect(collab.validationProblems(project, quote, isAdmin: false), ['Seul un administrateur peut valider un devis.']);
    await collabSync.syncNow();
    expect(collab.pendingCount, 0, reason: collabSync.lastError);
    expect(quote.number, isNull);

    // 2. L'administrateur reçoit le brouillon, le valide : le serveur attribue le numéro.
    await adminSync.syncNow();
    final adminProject = admin.project(project.id)!;
    final adminQuote = adminProject.quotes.singleWhere((q) => q.id == quote.id);
    final collabTotals = quoteTotals(project, quote);
    expect(quoteTotals(adminProject, adminQuote).ttc, collabTotals.ttc);
    expect(admin.validationProblems(adminProject, adminQuote, isAdmin: true), isEmpty);
    admin.validateQuote(adminProject, adminQuote, userId: adminSession.user!.id);
    await adminSync.syncNow();
    expect(adminQuote.syncError, isNull);
    expect(adminQuote.number, matches(RegExp(r'^DV-\d{4}-\d{4}$')));

    // 3. Le collaborateur reçoit le devis validé, numéroté et figé.
    await collabSync.syncNow();
    expect(quote.status, QuoteStatus.validated);
    expect(quote.number, adminQuote.number);
    collab.mutate(() => room.walls[0].length = 6, touch: project, room: room);
    expect(quoteTotals(project, quote).ttc, collabTotals.ttc, reason: 'quantités figées à la validation');
    // Une modification forcée d'un devis figé est refusée par le serveur.
    collab.editQuote(project, quote, () => quote.lines.first.unitPriceCents += 1);
    await collabSync.syncNow();
    expect(quote.syncError, contains('nouvelle version'));

    // 4. Envoi et acceptation par l'administrateur.
    admin.markSent(adminProject, adminQuote);
    await adminSync.syncNow();
    admin.decide(adminProject, adminQuote, accepted: true, note: 'Accord signé sur place');
    await adminSync.syncNow();
    expect(adminQuote.syncError, isNull);
    expect(adminQuote.status, QuoteStatus.accepted);

    // 5. Nouvelle version d'un devis validé : numéro « -v2 », l'ancienne est remplacée.
    final q2 = admin.createQuote(adminProject);
    admin.addLineFromWorkItem(adminProject, q2, admin.workItem(carrelage.id)!);
    await adminSync.syncNow();
    admin.mutate(() => adminProject.metreValidation = buildValidation(adminProject, userId: adminSession.user!.id, userName: 'Admin'),
        touch: adminProject, meta: true);
    admin.validateQuote(adminProject, q2, userId: adminSession.user!.id);
    await adminSync.syncNow();
    final v2 = admin.newVersion(adminProject, q2);
    admin.validateQuote(adminProject, v2, userId: adminSession.user!.id);
    await adminSync.syncNow();
    expect(q2.status, QuoteStatus.superseded);
    expect(v2.number, '${q2.number}-v2');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
