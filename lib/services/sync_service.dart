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

/// Implémentation vide : rien ne quitte le téléphone.
/// Les projets restent marqués « à synchroniser » tant qu'aucun backend n'est branché,
/// sauf si l'utilisateur simule le réseau dans le profil (démo).
class LocalOnlySyncService implements SyncService {
  @override
  Future<Set<String>> push(AppData data) async {
    if (!data.online) return {};
    return data.projects.where((p) => !p.synced).map((p) => p.id).toSet();
  }
}
