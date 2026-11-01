import 'package:flutter/foundation.dart';

/// Paramètres fixés à la compilation (`flutter build --dart-define=...`).
abstract final class AppConfig {
  /// Adresse de l'API LAMAALAM proposée par défaut (modifiable sur l'écran de connexion).
  static const defaultApiUrl = String.fromEnvironment('LAMAALAM_API_URL');

  /// Mode démonstration sans serveur. **Désactivé par défaut** ; uniquement pour des
  /// versions de test, tant qu'aucun serveur n'est hébergé (décision D-06).
  static const demoMode = bool.fromEnvironment('LAMAALAM_DEMO');
}

/// Vérifie l'adresse du serveur. HTTPS obligatoire, sauf en version de développement
/// pour un serveur local. Renvoie l'adresse normalisée (sans « / » final) ou null.
String? normalizeApiUrl(String input, {bool allowHttp = kDebugMode}) {
  final text = input.trim().replaceAll(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme == 'https') return text;
  if (uri.scheme == 'http' && allowHttp) return text;
  return null;
}
