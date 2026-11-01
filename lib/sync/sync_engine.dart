import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/app_state.dart';
import '../domain/models.dart';
import '../session/api_client.dart';
import '../session/session_controller.dart';

enum SyncPhase { idle, running, offline, error }

/// Synchronisation des fiches clients et projets avec le serveur (docs/ARCHITECTURE.md §3.4).
///
/// 1. Envoi des fiches modifiées sur le téléphone, avec la version de départ.
/// 2. Réception de tout ce qui a changé sur le serveur depuis la dernière fois.
/// Une divergence n'est jamais écrasée en silence : elle devient un [SyncConflict].
class SyncEngine extends ChangeNotifier {
  SyncEngine({required this.state, required this.session, this.debounce = const Duration(seconds: 3)}) {
    state.onLocalChange = schedule;
    session.addListener(_onSessionChange);
  }

  final AppState state;
  final SessionController session;
  final Duration debounce;

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
    // Les clients d'abord : un projet peut faire référence à un client créé hors ligne.
    final changes = <Map<String, dynamic>>[
      for (final c in _data.clients)
        if (c.dirty && c.syncError == null && !_inConflict('clients', c.id))
          {'entity': 'clients', 'id': c.id, 'base_version': c.serverVersion, 'deleted': c.deleted, 'data': c.toServer()},
      for (final p in _data.projects)
        if (p.dirty && p.syncError == null && !_inConflict('projects', p.id))
          {'entity': 'projects', 'id': p.id, 'base_version': p.serverVersion, 'deleted': p.deleted, 'data': p.toServer()},
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
    final local = _find(entity, id);
    if (local == null) return;
    final record = res['record'] == null ? null : Map<String, dynamic>.from(res['record'] as Map);
    // Une saisie faite pendant l'envoi garde la fiche « à envoyer ».
    final editedMeanwhile = sent != null &&
        !mapEquals(_serverData(local), Map<String, dynamic>.from(sent['data'] as Map)) ||
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
      if (local is Project && local.hasLocalOnlyData) {
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
    if (entity == 'clients') {
      _data.clients.add(Client(id: record['id'] as String));
    } else {
      _data.projects.add(Project(id: record['id'] as String));
    }
    _overwrite(_find(entity, record['id'] as String)!, record);
  }

  void _overwrite(Syncable local, Map<String, dynamic> record) {
    final data = Map<String, dynamic>.from(record['data'] as Map);
    if (local is Client) local.applyServer(data);
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
    final local = _find(c.entity, c.id);
    if (local != null) {
      local
        ..serverVersion = c.server['version'] as int
        ..markEdited();
    }
    _data.conflicts.remove(c);
    state.mutate(() {});
  }

  /// L'utilisateur garde la version du serveur. Les pièces, photos et devis locaux d'un
  /// projet sont conservés, sauf si le projet a été supprimé sur le serveur.
  void keepServer(SyncConflict c) {
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
    final list = entity == 'clients' ? _data.clients : _data.projects;
    for (final x in list) {
      if ((x as dynamic).id == id) return x;
    }
    return null;
  }

  void _remove(String entity, String id) {
    if (entity == 'clients') {
      _data.clients.removeWhere((c) => c.id == id);
    } else {
      _data.projects.removeWhere((p) => p.id == id);
    }
  }

  static Map<String, dynamic> _serverData(Syncable x) =>
      x is Client ? x.toServer() : (x as Project).toServer();

  /// Compare après normalisation par le même code (formats de date, espaces…).
  static bool _sameAsLocal(Syncable local, Map<String, dynamic> record) {
    if ((record['deleted'] == true) != local.deleted) return false;
    final data = Map<String, dynamic>.from(record['data'] as Map);
    final normalized = local is Client
        ? (Client(id: local.id)..applyServer(data)).toServer()
        : (Project(id: (local as Project).id)..applyServer(data)).toServer();
    return mapEquals(normalized, _serverData(local));
  }
}
