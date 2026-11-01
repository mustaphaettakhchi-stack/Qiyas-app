# LAMAALAM

Application mobile de Groupe LAMAALAM (Tanger) : relevé de biens, métrés, devis, suivi de chantier et espace client. Android et iOS (Flutter), serveur auto-hébergeable (FastAPI + PostgreSQL), composants Open Source uniquement.

Ce dépôt remplace l'ancien MVP « Qiyas » (décision D-01).

## État

| Élément | État |
| --- | --- |
| Phase 0 — audit et conception | Close (sauf décision D-06 sur l'hébergement) |
| Serveur : comptes, rôles, invitations, double authentification, journal d'audit | Fait, testé (99 tests serveur au total, sur PostgreSQL) |
| Application : relevé de pièces rectangulaires, métré, grille de prix, devis PDF, partage | Remplacé par les lots 1.3 à 1.6 (pièces de toute forme, métré validé, devis serveur) |
| Application : charte LAMAALAM, logo, aucune donnée de démonstration | Fait |
| Application : connexion au serveur, double authentification, invitation, gestion de l'équipe | Fait, testé de bout en bout contre le serveur réel |
| Clients et projets partagés entre téléphones (synchronisation, conflits, références `LMA-AAAA-NNNN`) | Fait, testé de bout en bout (pièces, devis et bibliothèque synchronisés depuis ; les photos restent sur le téléphone sauf celles partagées dans l'espace client) |
| Pièces de toute forme (mur par mur, angles), origine des cotes, contrôle de fermeture, plan, pièces synchronisées | Fait, testé (cas partagés application/serveur, bout en bout à deux téléphones) ; à valider sur 10 pièces réelles |
| Métré par lot et par pièce, éléments comptés, perte affichée, validation du métré | Fait, testé (unitaires et bout en bout) |
| Bibliothèque partagée (ouvrages, matériaux, fournisseurs), historique des prix, import CSV | Fait, testé ; démarre vide |
| Devis : versions, validation, numérotation serveur, TVA par taux, MAD/EUR, prix calculés, PDF Unicode | Fait, testé ; mentions légales à valider par l'expert-comptable |
| Tableau de bord (indicateurs, à faire, dernières opérations) | Fait, testé (indicateurs identiques à ceux du serveur) |
| Espace client en lecture seule (devis envoyés, photos partagées, étapes, messages, non-lus) | Fait, testé (client A contre client B) ; test d'intrusion manuel et essai avec 2 clients réels à faire |
| Exploitation : déploiement, sauvegarde chiffrée, restauration | Fait, exercice de restauration sur machine vierge à chaque modification (CI) ; **aucun hébergement en service (D-06)** |

## Documentation

| Document | Contenu |
| --- | --- |
| [`docs/PHASE0_DECISIONS.md`](docs/PHASE0_DECISIONS.md) | Audit, risques, décisions de Groupe LAMAALAM et réserves |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Architecture technique |
| [`docs/DATABASE_SCHEMA.md`](docs/DATABASE_SCHEMA.md) | Schéma de données cible |
| [`docs/USER_FLOWS.md`](docs/USER_FLOWS.md) | Parcours et critères d'acceptation |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Phases et état d'avancement |
| [`docs/INSTALLATION.md`](docs/INSTALLATION.md) | Installer un serveur et les téléphones |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Mettre à jour, revenir en arrière, surveiller |
| [`docs/BACKUP.md`](docs/BACKUP.md) / [`docs/RESTORE.md`](docs/RESTORE.md) | Sauvegardes chiffrées, restauration, exercice mensuel |
| [`docs/USER_GUIDE.md`](docs/USER_GUIDE.md) | Guide d'utilisation (équipe et clients) |
| [`docs/DEVELOPER_GUIDE.md`](docs/DEVELOPER_GUIDE.md) | Règles, tests, migrations, sécurité pour les développeurs |
| [`docs/TEST_REPORT.md`](docs/TEST_REPORT.md) | Rapport de tests de la phase 1 |
| [`SECURITY.md`](SECURITY.md) | Sécurité et données personnelles |
| [`OPEN_SOURCE_LICENSE_REGISTER.md`](OPEN_SOURCE_LICENSE_REGISTER.md) | Registre des licences |
| [`assets/branding/README.md`](assets/branding/README.md) | Fichiers du logo et réserves |

## Application mobile

Prérequis : Flutter ≥ 3.41.6 (testé avec 3.47.9), Android Studio ou Xcode (Xcode impose un Mac).

```bash
# Les dossiers natifs ne sont pas versionnés : les générer une fois
flutter create --platforms=android,ios --org ma.grouplamaalam --project-name lamaalam .
rm -f test/widget_test.dart

flutter pub get
flutter analyze
flutter test
flutter run --dart-define=LAMAALAM_API_URL=https://api.exemple.ma
```

L'adresse du serveur peut aussi être saisie sur l'écran de connexion (« Adresse du serveur ») ; seules les adresses `https://` sont acceptées hors version de développement.

Test de bout en bout application ↔ serveur (efface la base indiquée) :

```bash
LAMAALAM_TEST_DATABASE_URL=postgresql+psycopg://utilisateur:motdepasse@localhost:5432/lamaalam_test \
  PYTHON=backend/.venv/bin/python tool/integration_test.sh
```

À chaque push sur `main`, GitHub Actions analyse et teste l'application, teste le serveur et construit deux APK Android de test (onglet **Actions**, artefact `lamaalam-apk-test`) : `lamaalam-serveur.apk`, qui exige un serveur, et `lamaalam-demonstration-sans-serveur.apk`, utilisable tant qu'aucun hébergement n'est en service.

Permissions iOS à ajouter dans `ios/Runner/Info.plist` :

```xml
<key>NSCameraUsageDescription</key>
<string>LAMAALAM utilise l'appareil photo pour joindre des photos du chantier à vos relevés.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>LAMAALAM accède à vos photos pour les joindre à vos relevés.</string>
```

## Serveur

```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt

# Tests : base PostgreSQL de test (elle est entièrement effacée à chaque lancement)
export LAMAALAM_TEST_DATABASE_URL=postgresql+psycopg://utilisateur:motdepasse@localhost:5432/lamaalam_test
python -m pytest -q
```

Déploiement (aucun hébergement n'est encore validé, décision D-06) : [`docs/INSTALLATION.md`](docs/INSTALLATION.md), puis `deploy/deploy.sh`. Sauvegardes : [`docs/BACKUP.md`](docs/BACKUP.md).

## Organisation du code

```
lib/                     application Flutter (héritée de Qiyas, refonte modulaire prévue au lot 1.0)
  domain/                modèles et calculs de métré et de devis (fonctions pures, testées)
  data/                  état, stockage local, modèles de prestations (sans prix)
  session/               connexion au serveur : client API, jetons (stockage sécurisé), état de session
  services/              PDF, partage, télémètre (non branché)
  ui/                    écrans
test/                    tests Flutter ; test/support : données de référence réservées aux tests
backend/
  app/                   API FastAPI : config, modèles, sécurité, routes
  migrations/            migrations Alembic
  tests/                 tests sur PostgreSQL réel
deploy/                  Caddyfile, rôle applicatif PostgreSQL, scripts deploy / backup / restore
tool/                    test de bout en bout, exercice de restauration
assets/branding/         logo original et variantes
docker-compose.yml       pile serveur
```

## Ce qui est encore simulé dans l'application

| Fonction | État |
| --- | --- |
| Connexion | Réelle (serveur LAMAALAM). Une version « démonstration sans serveur » n'existe que si elle est compilée avec `--dart-define=LAMAALAM_DEMO=true` ; elle l'affiche en clair |
| Synchronisation | Réelle (clients, projets, pièces, devis, bibliothèque) ; la version « démonstration sans serveur » affiche « Sur ce téléphone » |
| Télémètre Bluetooth | Non branché ; le bouton de mesure simulée est masqué pour ne jamais produire de cote inventée (décision D-02) |
