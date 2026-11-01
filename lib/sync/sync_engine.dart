import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/app_state.dart';
import '../data/client_space.dart';
import '../domain/calculations.dart';
import '../domain/models.dart';
import '../session/api_client.dart';
import '../session/session_controller.dart';

enum SyncPhase { idle, running, offline, error }

/// Fabrique le PDF client d'un devis (lib/services/pdf_service.dart dans l'application).
typedef QuotePdfBuilder = Future<Uint8List> Function(Project project, Quote quote);

/// Synchronisation des fiches clients et projets avec le serveur (docs/ARCHITECTURE.md §3.4).
///
/// 1. Envoi des fiches modifiées sur le téléphone, avec la version de départ.
/// 2. Réception de tout ce qui a changé sur le serveur depuis la dernière fois.
/// Une divergence n'est jamais écrasée en silence : elle devient un [SyncConflict].
class SyncEngine extends ChangeNotifier {
  SyncEngine({required this.state, required this.session, this.debounce = const Duration(seconds: 3), this.pdfBuilder}) {
    state.onLocalChange = schedule;
    session.addListener(_onSessionChange);
  }

  final AppState state;
  final SessionController session;
  final Duration debounce;

  /// null : pas de publication automatique des PDF (tests).
  final QuotePdfBuilder? pdfBuilder;

  SyncPhase phase = SyncPhase.idle;
  String? lastError;
  Timer? _timer;
  Future<void>? _running;
  String? _syncedForUser;

  ApiClient get _api => session.api;
  AppData get _data => state.data;

  bool get enabled => session.isAuthenticated && !session.isDemo && (session.user?.isStaff ?? false);

  /// Synchronisation différée après une saisie (regroupe les frappes successives).
  void schedule() {
    if (!enabled) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => syncNow());
  }

  /// Lance une synchronisation (ou attend celle en cours).
  Future<void> syncNow() {
    if (!enabled) return Future.value();
    return _running ??= _run().whenComplete(() => _running = null);
  }

  /// Première synchronisation dès que la session est confirmée par le serveur.
  void _onSessionChange() {
    final uid = session.user?.id;
    if (!enabled || !session.verifiedOnline || uid == _syncedForUser) return;
    _syncedForUser = uid;
    syncNow();
  }

  @override
  void dispose() {
    session.removeListener(_onSessionChange);
    _timer?.cancel();
    if (state.onLocalChange == schedule) state.onLocalChange = null;
    super.dispose();
  }

  Future<void> _run() async {
    phase = SyncPhase.running;
    notifyListeners();
    try {
      if (!_checkAccount()) return;
      await _push();
      await _pull();
      await _publishPdfs();
      _data.lastSyncAt = DateTime.now();
      phase = SyncPhase.idle;
      lastError = null;
    } on ApiException catch (e) {
      phase = e.isNetwork ? SyncPhase.offline : SyncPhase.error;
      lastError = e.message;
    } finally {
      await state.afterSync();
      notifyListeners();
    }
  }

  /// Les données du téléphone appartiennent au premier compte qui les a synchronisées.
  /// Si un autre compte se connecte, la synchronisation est bloquée : sinon des fiches
  /// d'une personne (voire d'une autre entreprise) seraient envoyées sous un autre compte.
  bool _checkAccount() {
    final account = session.user?.id;
    if (_data.syncAccount == null) {
      _data.syncAccount = account;
      _data.syncCursor = 0;
    } else if (_data.syncAccount != account) {
      phase = SyncPhase.error;
      lastError = 'Ce téléphone contient les données d\'un autre compte : synchronisation bloquée. '
          'Contactez votre administrateur.';
      return false;
    }
    return true;
  }

  // ---------- envoi ----------

  bool _inConflict(String entity, String id) => _data.conflicts.any((c) => c.entity == entity && c.id == id);

  Future<void> _push() async {
    // Bibliothèque d'abord (administrateur seulement), puis clients, projets et pièces :
    // chaque fiche est envoyée après celles auxquelles elle fait référence.
    final admin = session.user?.isAdmin ?? false;
    Map<String, dynamic> lib(String entity, Syncable x) =>
        {'entity': entity, 'id': (x as dynamic).id, 'base_version': x.serverVersion, 'deleted': x.deleted, 'data': _serverData(x)};
    final changes = <Map<String, dynamic>>[
      if (admin) ...[
        for (final x in _data.suppliers)
          if (x.dirty && x.syncError == null && !_inConflict('suppliers', x.id)) lib('suppliers', x),
        for (final x in _data.materials)
          if (x.dirty && x.syncError == null && !_inConflict('materials', x.id)) lib('materials', x),
        for (final x in _data.workItems)
          if (x.dirty && x.syncError == null && !_inConflict('work_items', x.id)) lib('work_items', x),
      ],
      for (final c in _data.clients)
        if (c.dirty && c.syncError == null && !_inConflict('clients', c.id))
          {'entity': 'clients', 'id': c.id, 'base_version': c.serverVersion, 'deleted': c.deleted, 'data': c.toServer()},
      for (final p in _data.projects)
        if (p.dirty && p.syncError == null && !_inConflict('projects', p.id))
          {'entity': 'projects', 'id': p.id, 'base_version': p.serverVersion, 'deleted': p.deleted, 'data': p.toServer()},
      // Les pièces après leur projet ; celles d'un projet supprimé ici ne sont pas envoyées.
      for (final p in _data.projects)
        if (!p.deleted)
          for (final r in p.rooms)
            if (r.dirty && r.syncError == null && !_inConflict('rooms', r.id))
              {'entity': 'rooms', 'id': r.id, 'base_version': r.serverVersion, 'deleted': false, 'data': r.toServer(p.id)},
      // Devis après les pièces : leurs quantités dépendent du métré.
      for (final p in _data.projects)
        if (!p.deleted)
          for (final q in p.quotes)
            if (q.dirty && !q.legacy && q.syncError == null && !_inConflict('quotes', q.id))
              {'entity': 'quotes', 'id': q.id, 'base_version': q.serverVersion, 'deleted': false, 'data': quoteToServer(p, q)},
      for (final t in _data.roomTombstones)
        if (t.syncError == null && !_inConflict('rooms', t.id))
          {'entity': 'rooms', 'id': t.id, 'base_version': t.serverVersion, 'deleted': true, 'data': <String, dynamic>{}},
    ];
    for (var i = 0; i < changes.length; i += 200) {
      final batch = changes.sublist(i, i + 200 > changes.length ? changes.length : i + 200);
      final sent = {for (final c in batch) '${c['entity']}/${c['id']}': c};
      final r = await _api.post('/sync/push', {'changes': batch}) as Map;
      for (final raw in r['results'] as List) {
        final res = Map<String, dynamic>.from(raw as Map);
        final entity = res['entity'] as String;
        final id = res['id'] as String;
        _handleResult(entity, id, res, sent['$entity/$id']);
      }
    }
  }

  void _handleResult(String entity, String id, Map<String, dynamic> res, Map<String, dynamic>? sent) {
    if (entity == 'rooms' && sent?['deleted'] == true) {
      _handleTombstoneResult(id, res);
      return;
    }
    final local = _find(entity, id);
    if (local == null) return;
    final record = res['record'] == null ? null : Map<String, dynamic>.from(res['record'] as Map);
    // Une saisie faite pendant l'envoi garde la fiche « à envoyer ».
    final editedMeanwhile = sent != null &&
        jsonEncode(_serverData(local)) != jsonEncode(sent['data']) ||
        (sent != null && sent['deleted'] != local.deleted);
    switch (res['status']) {
      case 'applied':
        if (record == null) {
          // Créée puis supprimée hors ligne : rien n'existe sur le serveur.
          if (local.deleted) _remove(entity, id);
          return;
        }
        if (local.deleted && record['deleted'] == true) {
          _remove(entity, id);
          return;
        }
        if (!editedMeanwhile) {
          // Le serveur peut compléter ou normaliser la fiche (responsable du projet,
          // adresse e-mail…) : on reprend sa version, les données locales restant intactes.
          _overwrite(local, record);
        } else {
          local.serverVersion = record['version'] as int;
          if (local is Project) {
            local.reference = record['reference'] as String?;
            local.managerId ??= (record['data'] as Map)['manager_id'] as String?;
          }
        }
      case 'conflict':
        if (record != null && _sameAsLocal(local, record)) {
          local
            ..serverVersion = record['version'] as int
            ..dirty = false;
          if (local is Project) local.reference = record['reference'] as String?;
        } else if (record != null) {
          _addConflict(entity, id, record, res['message'] as String? ?? 'Modifié entre-temps sur le serveur.');
        }
      case 'rejected':
        local.syncError = res['message'] as String? ?? 'Refusé par le serveur.';
    }
  }

  void _handleTombstoneResult(String id, Map<String, dynamic> res) {
    final t = _data.roomTombstones.where((x) => x.id == id).firstOrNull;
    if (t == null) return;
    final record = res['record'] == null ? null : Map<String, dynamic>.from(res['record'] as Map);
    switch (res['status']) {
      case 'applied':
        _data.roomTombstones.remove(t);
      case 'conflict':
        if (record != null && record['deleted'] == true) {
          _data.roomTombstones.remove(t);
        } else if (record != null) {
          _addConflict('rooms', id, record, 'Pièce supprimée sur ce téléphone mais modifiée entre-temps sur le serveur.');
        }
      case 'rejected':
        // Pièce déjà inaccessible ou disparue côté serveur : rien à supprimer de plus.
        _data.roomTombstones.remove(t);
    }
  }

  // ---------- PDF des devis envoyés (espace client) ----------

  /// Devis dont le PDF peut être déposé : envoyé depuis ce téléphone, synchronisé,
  /// numéroté et encore à l'état envoyé, accepté ou refusé sur le serveur.
  static bool pdfPublishable(Quote q) =>
      q.clientPdfPending &&
      !q.dirty &&
      !q.legacy &&
      q.syncError == null &&
      q.serverVersion != null &&
      q.number != null &&
      (q.status == QuoteStatus.sent || q.status == QuoteStatus.accepted || q.status == QuoteStatus.refused);

  Future<void> _publishPdfs() async {
    if (pdfBuilder == null) return;
    for (final p in _data.projects) {
      if (p.deleted) continue;
      for (final q in p.quotes) {
        if (!pdfPublishable(q) || _inConflict('quotes', q.id)) continue;
        try {
          await publishQuotePdf(p, q);
        } on ApiException catch (e) {
          if (e.isNetwork) rethrow;
          // Refus ponctuel : nouvel essai à la prochaine synchronisation, la fiche
          // « Espace client » du projet affiche le PDF comme non publié.
        }
      }
    }
  }

  /// Dépose le PDF du devis pour le client. Un PDF déjà présent sur le serveur (409)
  /// vaut publication : le serveur n'en garde qu'un par devis et ne le remplace jamais.
  Future<void> publishQuotePdf(Project p, Quote q) async {
    final builder = pdfBuilder;
    if (builder == null) throw const ApiException('Publication du PDF indisponible.', status: 0);
    try {
      await ClientSpaceApi(_api).uploadQuotePdf(p.id, q.id, await builder(p, q));
    } on ApiException catch (e) {
      if (e.status != 409) rethrow;
    }
    q.clientPdfPending = false;
    await state.afterSync();
    notifyListeners();
  }

  // ---------- réception ----------

  Future<void> _pull() async {
    var more = true;
    while (more) {
      final r = Map<String, dynamic>.from(await _api.get('/sync/pull?cursor=${_data.syncCursor}') as Map);
      for (final raw in r['records'] as List) {
        _applyRecord(Map<String, dynamic>.from(raw as Map));
      }
      _data.syncCursor = r['cursor'] as int;
      more = r['has_more'] == true;
    }
  }

  void _applyRecord(Map<String, dynamic> record) {
    final entity = record['entity'] as String;
    final id = record['id'] as String;
    final deleted = record['deleted'] == true;
    final local = _find(entity, id);

    if (entity == 'rooms') {
      final t = _data.roomTombstones.where((x) => x.id == id).firstOrNull;
      if (t != null) {
        if (deleted) {
          _data.roomTombstones.remove(t);
        } else if (record['version'] != t.serverVersion) {
          _addConflict('rooms', id, record, 'Pièce supprimée sur ce téléphone mais modifiée entre-temps sur le serveur.');
        }
        return;
      }
    }
    if (local == null) {
      if (!deleted) _insertFromServer(entity, record);
      return;
    }
    if (local.serverVersion == record['version'] && local.deleted == deleted) return; // notre propre envoi

    if (local.dirty) {
      if (_sameAsLocal(local, record)) {
        local
          ..serverVersion = record['version'] as int
          ..dirty = false;
      } else {
        _addConflict(entity, id, record, 'Modifié à la fois sur ce téléphone et sur le serveur.');
      }
      return;
    }
    if (deleted) {
      if (local is Room && local.photoPaths.isNotEmpty) {
        _addConflict(entity, id, record, 'Pièce supprimée sur le serveur, mais ses photos sont sur ce téléphone.');
      } else if (local is Project && local.hasLocalOnlyData) {
        _addConflict(entity, id, record,
            'Supprimé sur le serveur, mais ce téléphone contient des pièces, photos ou devis de ce projet.');
      } else {
        _remove(entity, id);
      }
      return;
    }
    _overwrite(local, record);
  }

  void _insertFromServer(String entity, Map<String, dynamic> record) {
    final id = record['id'] as String;
    switch (entity) {
      case 'suppliers':
        _data.suppliers.add(Supplier(id: id, name: ''));
      case 'materials':
        _data.materials.add(MaterialItem(id: id, name: ''));
      case 'work_items':
        _data.workItems.add(WorkItem(id: id, name: ''));
      case 'clients':
        _data.clients.add(Client(id: id));
      case 'projects':
        _data.projects.add(Project(id: id));
      case 'rooms' || 'quotes':
        final projectId = (record['data'] as Map)['project_id'] as String?;
        final project = _data.projects.where((p) => p.id == projectId).firstOrNull;
        if (project == null) {
          // Pièce ou devis reçu avant son projet : rattaché à l'arrivée du projet.
          _data.pendingRooms
            ..removeWhere((r) => r['id'] == id)
            ..add(record);
          return;
        }
        if (entity == 'rooms') {
          project.rooms.add(Room(id: id, name: '', height: 2.8));
        } else {
          project.quotes.add(Quote(id: id, estimateId: (record['data'] as Map)['estimate_id'] as String?, date: DateTime.now()));
        }
    }
    _overwrite(_find(entity, id)!, record);
    if (entity == 'projects') _attachPendingRooms(id);
  }

  void _attachPendingRooms(String projectId) {
    final waiting = _data.pendingRooms.where((r) => (r['data'] as Map)['project_id'] == projectId).toList();
    for (final r in waiting) {
      _data.pendingRooms.remove(r);
      final entity = r['entity'] as String? ?? 'rooms';
      if (r['deleted'] != true && _find(entity, r['id'] as String) == null) _insertFromServer(entity, r);
    }
  }

  void _overwrite(Syncable local, Map<String, dynamic> record) {
    final data = Map<String, dynamic>.from(record['data'] as Map);
    if (local is Client) local.applyServer(data);
    if (local is Room) local.applyServer(data);
    if (local is Quote) local.applyServer(data, reference: record['reference'] as String?);
    if (local is WorkItem) local.applyServer(data);
    if (local is MaterialItem) local.applyServer(data);
    if (local is Supplier) local.applyServer(data);
    if (local is Project) {
      local
        ..applyServer(data)
        ..reference = record['reference'] as String?
        ..updatedAt = DateTime.tryParse(record['updated_at'] as String? ?? '')?.toLocal() ?? local.updatedAt;
    }
    local
      ..serverVersion = record['version'] as int
      ..dirty = false
      ..deleted = false
      ..syncError = null;
  }

  // ---------- conflits ----------

  void _addConflict(String entity, String id, Map<String, dynamic> record, String reason) {
    _data.conflicts.removeWhere((c) => c.entity == entity && c.id == id);
    _data.conflicts.add(SyncConflict(entity: entity, id: id, server: record, reason: reason));
  }

  /// L'utilisateur garde sa version : elle sera renvoyée en s'appuyant sur la version du serveur.
  void keepMine(SyncConflict c) {
    final t = c.entity == 'rooms' ? _data.roomTombstones.where((x) => x.id == c.id).firstOrNull : null;
    if (t != null) {
      t
        ..serverVersion = c.server['version'] as int
        ..syncError = null;
    }
    final local = _find(c.entity, c.id);
    if (local != null) {
      local
        ..serverVersion = c.server['version'] as int
        ..markEdited();
      // Projet restauré : ses pièces refusées faute de projet peuvent repartir.
      if (local is Project) {
        for (final r in local.rooms.where((r) => r.syncError != null)) {
          r.syncError = null;
        }
      }
    }
    _data.conflicts.remove(c);
    state.mutate(() {});
  }

  /// L'utilisateur garde la version du serveur. Les pièces, photos et devis locaux d'un
  /// projet sont conservés, sauf si le projet a été supprimé sur le serveur.
  void keepServer(SyncConflict c) {
    final t = c.entity == 'rooms' ? _data.roomTombstones.where((x) => x.id == c.id).firstOrNull : null;
    if (t != null) {
      _data.roomTombstones.remove(t);
      if (c.server['deleted'] != true) _insertFromServer('rooms', c.server);
    }
    final local = _find(c.entity, c.id);
    if (local != null) {
      if (c.server['deleted'] == true) {
        _remove(c.entity, c.id);
      } else {
        _overwrite(local, c.server);
      }
    }
    _data.conflicts.remove(c);
    state.mutate(() {});
  }

  // ---------- outils ----------

  Syncable? _find(String entity, String id) {
    switch (entity) {
      case 'suppliers':
        return _data.suppliers.where((x) => x.id == id).firstOrNull;
      case 'materials':
        return _data.materials.where((x) => x.id == id).firstOrNull;
      case 'work_items':
        return _data.workItems.where((x) => x.id == id).firstOrNull;
      case 'clients':
        return _data.clients.where((c) => c.id == id).firstOrNull;
      case 'projects':
        return _data.projects.where((p) => p.id == id).firstOrNull;
      case 'quotes':
        for (final p in _data.projects) {
          for (final q in p.quotes) {
            if (q.id == id) return q;
          }
        }
        return null;
      default:
        for (final p in _data.projects) {
          for (final r in p.rooms) {
            if (r.id == id) return r;
          }
        }
        return null;
    }
  }

  Project? _projectOfQuote(String quoteId) => _data.projects.where((p) => p.quotes.any((q) => q.id == quoteId)).firstOrNull;

  Project? _projectOfRoom(String roomId) => _data.projects.where((p) => p.rooms.any((r) => r.id == roomId)).firstOrNull;

  void _remove(String entity, String id) {
    switch (entity) {
      case 'suppliers':
        _data.suppliers.removeWhere((x) => x.id == id);
      case 'materials':
        _data.materials.removeWhere((x) => x.id == id);
      case 'work_items':
        _data.workItems.removeWhere((x) => x.id == id);
      case 'clients':
        _data.clients.removeWhere((c) => c.id == id);
      case 'projects':
        _data.projects.removeWhere((p) => p.id == id);
      case 'quotes':
        _projectOfQuote(id)?.quotes.removeWhere((q) => q.id == id);
      default:
        _projectOfRoom(id)?.rooms.removeWhere((r) => r.id == id);
    }
  }

  Map<String, dynamic> _serverData(Syncable x) => switch (x) {
        Client() => x.toServer(),
        Project() => x.toServer(),
        Room() => x.toServer(_projectOfRoom(x.id)?.id ?? ''),
        Quote() => quoteToServer(_projectOfQuote(x.id) ?? Project(id: ''), x),
        WorkItem() => x.toServer(),
        MaterialItem() => x.toServer(),
        Supplier() => x.toServer(),
        _ => const {},
      };

  /// Compare après normalisation par le même code (formats de date, nombres, espaces…).
  bool _sameAsLocal(Syncable local, Map<String, dynamic> record) {
    if ((record['deleted'] == true) != local.deleted) return false;
    final data = Map<String, dynamic>.from(record['data'] as Map);
    final normalized = switch (local) {
      Client() => (Client(id: local.id)..applyServer(data)).toServer(),
      Project() => (Project(id: local.id)..applyServer(data)).toServer(),
      Room() => (Room(id: local.id, name: '', height: 2.8)..applyServer(data)).toServer(_projectOfRoom(local.id)?.id ?? ''),
      Quote() => quoteToServer(
          _projectOfQuote(local.id) ?? Project(id: ''),
          Quote(id: local.id, estimateId: local.estimateId, date: local.date)..applyServer(data, reference: local.number),
        ),
      WorkItem() => (WorkItem(id: local.id, name: '')..applyServer(data)).toServer(),
      MaterialItem() => (MaterialItem(id: local.id, name: '')..applyServer(data)).toServer(),
      Supplier() => (Supplier(id: local.id, name: '')..applyServer(data)).toServer(),
      _ => const <String, dynamic>{},
    };
    return jsonEncode(normalized) == jsonEncode(_serverData(local));
  }
}
