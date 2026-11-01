import 'dart:async';

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'session_store.dart';

/// Erreur lisible par l'utilisateur. [status] vaut null quand le serveur n'a pas répondu.
class ApiException implements Exception {
  const ApiException(this.message, {this.status});
  final String message;
  final int? status;

  bool get isNetwork => status == null;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

/// Client HTTP de l'API LAMAALAM : jeton d'accès en mémoire, jeton de rafraîchissement
/// dans le stockage sécurisé, renouvellement automatique sur réponse 401.
class ApiClient {
  ApiClient({required this.store, Dio? dio}) : _dio = dio ?? Dio();

  final SessionStore store;
  final Dio _dio;
  String? _baseUrl;
  String? _accessToken;
  Completer<bool>? _refreshing;

  /// Appelé quand la session est définitivement refusée par le serveur.
  void Function()? onSessionRevoked;

  String? get baseUrl => _baseUrl;
  bool get hasAccessToken => _accessToken != null;

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    await store.write(SessionKeys.apiUrl, url);
  }

  Future<void> loadBaseUrl(String fallback) async {
    _baseUrl = await store.read(SessionKeys.apiUrl) ?? (fallback.isEmpty ? null : fallback);
  }

  Future<void> saveTokens(Map<String, dynamic> tokens) async {
    _accessToken = tokens['access_token'] as String;
    await store.write(SessionKeys.refreshToken, tokens['refresh_token'] as String);
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    await store.delete(SessionKeys.refreshToken);
  }

  /// Renouvelle la session. true = renouvelée ; false = refusée (session révoquée ou expirée).
  /// Lève [ApiException] réseau si le serveur est injoignable.
  Future<bool> refresh() async {
    final pending = _refreshing;
    if (pending != null) return pending.future;
    final c = _refreshing = Completer<bool>();
    c.future.ignore(); // l'erreur éventuelle est relancée à l'appelant ci-dessous
    try {
      final token = await store.read(SessionKeys.refreshToken);
      if (token == null) {
        c.complete(false);
        return false;
      }
      try {
        final data = await _send('POST', '/auth/refresh', body: {'refresh_token': token}, auth: false);
        await saveTokens(Map<String, dynamic>.from(data as Map));
        c.complete(true);
      } on ApiException catch (e) {
        if (e.isNetwork) rethrow;
        await clearTokens();
        c.complete(false);
      }
      return await c.future;
    } catch (e, st) {
      if (!c.isCompleted) c.completeError(e, st);
      rethrow;
    } finally {
      _refreshing = null;
    }
  }

  Future<dynamic> get(String path) => _authed('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _authed('POST', path, body: body);
  Future<dynamic> patch(String path, Object body) => _authed('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _authed('DELETE', path);

  /// Requête sans session (connexion, invitation).
  Future<dynamic> postPublic(String path, Object body) => _send('POST', path, body: body, auth: false);

  /// Envoi d'un fichier (formulaire multipart). Le formulaire est reconstruit si la
  /// requête doit être rejouée après renouvellement de la session.
  Future<dynamic> upload(String path, {required Map<String, String> fields, required Uint8List bytes, required String filename}) =>
      _authed('POST', path, body: () => FormData.fromMap({...fields, 'file': MultipartFile.fromBytes(bytes, filename: filename)}));

  /// Téléchargement par lien signé (`/api/v1/files/download/...`, valable 15 minutes).
  /// Le lien porte sa propre autorisation : aucun jeton n'est envoyé.
  Future<Uint8List> download(String signedPath) async {
    // Le chemin vient du serveur : il ne doit désigner que le téléchargement de fichiers
    // de ce même serveur (jamais un autre hôte).
    if (!RegExp(r'^/api/v1/files/download/[0-9a-f-]+\?[A-Za-z0-9=&_.%-]+$').hasMatch(signedPath)) {
      throw const ApiException('Lien de téléchargement invalide.', status: 0);
    }
    final r = await _send('GET', signedPath, auth: false, raw: true);
    return Uint8List.fromList(r as List<int>);
  }

  Future<dynamic> _authed(String method, String path, {Object? body}) async {
    if (_accessToken == null && !await refresh()) {
      onSessionRevoked?.call();
      throw const ApiException('Session expirée. Reconnectez-vous.', status: 401);
    }
    Object? data() => body is Object? Function() ? body() : body;
    try {
      return await _send(method, path, body: data(), auth: true);
    } on ApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      if (!await refresh()) {
        onSessionRevoked?.call();
        rethrow;
      }
      return _send(method, path, body: data(), auth: true);
    }
  }

  /// [raw] : [path] est un chemin complet du serveur (lien signé) et la réponse est binaire.
  Future<dynamic> _send(String method, String path, {Object? body, required bool auth, bool raw = false}) async {
    final base = _baseUrl;
    if (base == null) throw const ApiException('Adresse du serveur non renseignée.', status: 0);
    try {
      final r = await _dio.request<dynamic>(
        raw ? '$base$path' : '$base/api/v1$path',
        data: body,
        options: Options(
          method: method,
          headers: {if (auth && _accessToken != null) 'Authorization': 'Bearer $_accessToken'},
          responseType: raw ? ResponseType.bytes : null,
          sendTimeout: Duration(seconds: body is FormData ? 120 : 20),
          receiveTimeout: Duration(seconds: raw ? 120 : 30),
          validateStatus: (_) => true,
        ),
      );
      final code = r.statusCode ?? 0;
      if (code >= 200 && code < 300) return r.data;
      throw ApiException(_message(r), status: code);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badCertificate) {
        throw const ApiException('Le certificat de sécurité du serveur est invalide. Connexion refusée.', status: 0);
      }
      throw const ApiException(
        'Serveur injoignable. Vérifiez la connexion internet ; vos données restent sur le téléphone.',
      );
    }
  }

  static String _message(Response<dynamic> r) {
    final data = r.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
    if (data is Map && data['detail'] is List) return 'Informations incomplètes ou invalides.';
    return switch (r.statusCode) {
      401 => 'Session expirée. Reconnectez-vous.',
      403 => 'Action réservée à un autre profil.',
      404 => 'Élément introuvable.',
      410 => 'Lien expiré. Réessayez.',
      413 => 'Fichier trop volumineux (15 Mo au maximum).',
      429 => 'Trop de tentatives. Réessayez dans quelques minutes.',
      _ => 'Le serveur a rencontré une erreur (${r.statusCode}). Réessayez plus tard.',
    };
  }
}
