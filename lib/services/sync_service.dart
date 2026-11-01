import '../domain/models.dart';

/// Synchronisation avec le serveur.
///
/// Choix « local d'abord » : toutes les données vivent sur le téléphone
/// (data/local_store.dart). Ce contrat est prêt pour brancher Firebase,
/// Supabase ou une API maison sans toucher aux écrans.
abstract class SyncService {
  /// Envoie les projets modifiés. Renvoie les identifiants synchronisés.
  Future<Set<String>> push(AppData data);
}

/// Implémentation vide : rien ne quitte le téléphone, donc aucun projet n'est jamais
/// déclaré synchronisé. Remplacée par la synchronisation avec l'API LAMAALAM (lot 1.2).
class LocalOnlySyncService implements SyncService {
  @override
  Future<Set<String>> push(AppData data) async => {};
}
