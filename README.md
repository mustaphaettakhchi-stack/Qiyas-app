# Qiyas – application Flutter (MVP)

Qiyas transforme une visite de chantier en **plan coté, métré automatique et devis en dirhams**, prêt à envoyer par WhatsApp. Cible : artisans et petites entreprises de rénovation au Maroc.

Ce dépôt implémente les 10 écrans du cahier des charges du MVP, en version **« local d'abord »** : toutes les données restent sur le téléphone, et les services externes (SMS, synchronisation, télémètre) sont branchés derrière des interfaces, avec une implémentation de démonstration.

## Démarrer

Prérequis : Flutter 3.41.6 ou plus récent (Dart 3.11+), Android Studio ou Xcode.

```bash
# 1. Générer les dossiers natifs (non versionnés)
flutter create --platforms=android,ios --org ma.qiyas --project-name qiyas .
rm -f test/widget_test.dart   # fichier d'exemple généré, inutile ici

# 2. Installer et lancer
flutter pub get
flutter test
flutter run
```

**Connexion de démonstration** : n'importe quel numéro marocain valide (ex. 0661234567), puis le code `482913`.

### Permissions iOS

Ajouter dans `ios/Runner/Info.plist` :

```xml
<key>NSCameraUsageDescription</key>
<string>Qiyas utilise l'appareil photo pour joindre des photos du chantier à vos relevés.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Qiyas accède à vos photos pour les joindre à vos relevés.</string>
```

Android ne demande aucune permission supplémentaire pour le MVP.

## APK de test

À chaque push sur `main`, GitHub Actions analyse le code, lance les tests et construit un APK Android de test. Il se télécharge dans l'onglet **Actions**, dernier passage, section **Artifacts** (`qiyas-debug-apk`). Le rapport détaillé est publié sur la branche `ci-results`.

## Architecture

```
lib/
  main.dart                  injection des services
  app.dart                   thème, langue, porte d'entrée (connexion ou accueil)
  domain/
    models.dart              Entreprise, Prestation, Projet, Pièce, Ouverture, Devis, Ligne
    calculations.dart        règles de calcul (fonctions pures, testées)
  data/
    app_state.dart           état central (ChangeNotifier) : chaque modification est sauvegardée
    local_store.dart         stockage JSON + photos dans le dossier privé de l'app
    sample_data.dart         données d'exemple et grilles modèles par métier
  services/
    auth_service.dart        connexion SMS (simulée)
    sync_service.dart        synchronisation (locale uniquement pour l'instant)
    laser_meter_service.dart télémètre Bluetooth (simulé)
    pdf_service.dart         devis PDF A4, généré hors connexion
    share_service.dart       partage du PDF et ouverture de WhatsApp
  ui/
    home_shell.dart          onglets Projets, Prix, Profil
    screens/                 un fichier par écran du cahier des charges
    widgets/                 champs, pastilles, photos
test/
  calculations_test.dart     cas de test de référence et règles de calcul
```

| Écran | Fichier |
| --- | --- |
| E1 Inscription et connexion | `ui/screens/login_screen.dart` |
| E2 Profil de l'entreprise | `ui/screens/profile_screen.dart` |
| E3 Liste des projets | `ui/screens/projects_screen.dart` |
| E4 Fiche projet | `ui/screens/project_screen.dart` |
| E5 Saisie d'une pièce | `ui/screens/room_screen.dart` |
| E6 Plan | `ui/screens/plan_screen.dart` |
| E7 Métré | `ui/screens/metre_screen.dart` |
| E8 Grille de prix | `ui/screens/prices_screen.dart` |
| E9 Édition du devis | `ui/screens/quote_screen.dart` |
| E10 Aperçu PDF et partage | `ui/screens/preview_screen.dart` |

## Cas de test de référence

Projet d'exemple « M. Benali », 5 pièces : sol 51,66 m², murs nets 163,03 m², plinthes 60,08 ml. Devis peinture murs 45, peinture plafond 50, carrelage 280, plinthes 60 MAD : **27 989 MAD HT, 5 598 MAD de TVA, 33 587 MAD TTC**. Vérifié par `test/calculations_test.dart`.

## Ce qui est simulé

| Fonction | État | Pour la rendre réelle |
| --- | --- | --- |
| SMS de connexion | Code fixe `482913` | Implémenter `AuthService` avec le fournisseur SMS retenu |
| Synchronisation | Aucune donnée ne quitte le téléphone ; interrupteur « Réseau disponible » dans le profil | Implémenter `SyncService` (Firebase, Supabase ou API maison) |
| Numérotation des devis | Compteur local | Réserve de 20 numéros par appareil attribuée par le serveur |
| Télémètre Bluetooth | Mesure générée | Implémenter `LaserMeterService` (ex. `flutter_blue_plus`) selon le modèle retenu |
| Envoi WhatsApp | Réel : menu de partage du PDF, ou conversation WhatsApp avec le texte | — |

## Reste à faire avant le lancement

- Embarquer une police Unicode (Noto Sans et Noto Sans Arabic) dans le PDF : la police intégrée ne couvre que l'alphabet latin, un nom de client en arabe ne s'afficherait pas.
- Externaliser les textes dans des fichiers ARB (`flutter gen-l10n`) pour préparer l'arabe et la darija.
- Brancher le backend, le fournisseur SMS et le télémètre (questions ouvertes du cahier des charges).
- Valider les mentions légales du devis avec un expert-comptable.
- Tester sur un Android d'entrée de gamme (3 Go de RAM) : temps d'ouverture et génération du PDF.
- Déclaration CNDP, icône et nom de l'application, publication en accès anticipé.
