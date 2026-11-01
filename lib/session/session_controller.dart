import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/config.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'session_store.dart';

/// État de connexion de l'application.
///
/// Hors connexion, un utilisateur déjà connecté retrouve son espace grâce au profil
/// mémorisé : ses données sont sur le téléphone. La session est vérifiée auprès du
/// serveur dès que le réseau revient ; si le serveur la refuse, l'utilisateur est déconnecté.
class SessionController extends ChangeNotifier {
  SessionController({required this.api, required this.auth, required this.store}) {
    api.onSessionRevoked = _revoked;
  }

  final ApiClient api;
  final AuthService auth;
  final SessionStore store;

  UserProfile? _user;
  bool _demo = false;
  bool _restored = false;
  bool _verifiedOnline = false;

  UserProfile? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isDemo => _demo;
  bool get restored => _restored;

  /// true si la session a été confirmée par le serveur depuis le lancement.
  bool get verifiedOnline => _verifiedOnline;

  Future<void> restore() async {
    await api.loadBaseUrl(AppConfig.defaultApiUrl);
    final cached = await store.read(SessionKeys.profile);
    final refresh = await store.read(SessionKeys.refreshToken);
    if (cached != null && refresh != null) {
      try {
        _user = UserProfile.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {
        await store.delete(SessionKeys.profile);
      }
    }
    _restored = true;
    notifyListeners();
    if (_user != null) await verify();
  }

  /// Vérifie la session auprès du serveur. Sans réseau, l'utilisateur reste connecté localement.
  Future<void> verify() async {
    try {
      if (!await api.refresh()) {
        await _revoked();
        return;
      }
      await _setUser(await auth.me());
      _verifiedOnline = true;
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _revoked();
      // Erreur réseau : on reste connecté hors ligne.
    }
  }

  /// À appeler une fois les jetons obtenus (connexion ou double authentification terminée).
  Future<void> completeLogin() async {
    await _setUser(await auth.me());
    _verifiedOnline = true;
    notifyListeners();
  }

  void enterDemo() {
    assert(AppConfig.demoMode, 'Mode démonstration non compilé');
    if (!AppConfig.demoMode) return;
    _demo = true;
    _user = const UserProfile(
      id: 'demo',
      organizationId: 'demo',
      email: 'demonstration@lamaalam.invalid',
      fullName: 'Démonstration',
      roles: ['collaborator'],
      totpEnabled: false,
    );
    notifyListeners();
  }

  Future<void> logout() async {
    if (!_demo) await auth.logout();
    await _clear();
  }

  Future<void> _setUser(UserProfile u) async {
    _user = u;
    await store.write(SessionKeys.profile, jsonEncode(u.toJson()));
  }

  Future<void> _revoked() async {
    await api.clearTokens();
    await _clear();
  }

  Future<void> _clear() async {
    _user = null;
    _demo = false;
    _verifiedOnline = false;
    await store.delete(SessionKeys.profile);
    notifyListeners();
  }
}
