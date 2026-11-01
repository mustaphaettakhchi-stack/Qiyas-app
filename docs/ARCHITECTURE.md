# Architecture — LAMAALAM

Version 0.1 — 1er novembre 2026 — statut : **PROPOSITION, à valider** (voir [`PHASE0_DECISIONS.md`](PHASE0_DECISIONS.md))

## 1. Principes

1. **Le téléphone ne fait jamais de calcul lourd.** Capture, saisie, métré, devis et PDF sur le téléphone ; reconstruction 3D, rendus et montage vidéo sur le serveur, en tâches asynchrones.
2. **Hors ligne d'abord.** Toute saisie est écrite d'abord dans la base locale, puis synchronisée. L'utilisateur n'attend jamais le réseau pour enregistrer.
3. **Le serveur fait autorité pour les droits.** Toute règle d'accès est appliquée par l'API et la base (filtres par organisation et par client), l'interface mobile ne fait que masquer.
4. **Calculs déterministes et traçables.** Métrés et devis sont des fonctions pures, versionnées, testées ; chaque quantité garde la trace de son origine (pièce, mesure, formule, coefficient).
5. **Aucune dépendance SaaS.** Tous les composants tournent sur un serveur Linux maîtrisé par LAMAALAM, via Docker Compose.
6. **Une seule source de vérité métier par règle.** Les formules de métré sont implémentées en Dart (téléphone, hors ligne) et contrôlées côté serveur par une suite de **cas de test partagés** (fichiers JSON d'entrées/sorties attendues) exécutée par les deux implémentations.

## 2. Vue d'ensemble

```
┌──────────────────────── Smartphone (Flutter, Android / iOS) ────────────────────────┐
│  UI (écrans, design system)                                                         │
│  ├─ État : Riverpod                     ├─ Navigation : go_router (gardes de rôle)  │
│  Domaine (Dart pur) : métrés, devis, validation des mesures                         │
│  Données : Drift (SQLite) + file d'opérations à synchroniser + fichiers médias      │
│  Services : caméra, contrôle qualité image (netteté, exposition), PDF, partage      │
└───────────────────────────────┬─────────────────────────────────────────────────────┘
                                │ HTTPS (TLS 1.2+), JWT court + jeton de rafraîchissement
┌───────────────────────────────▼──────────────── Serveur Linux (Docker Compose) ──────┐
│  Caddy (reverse proxy, certificats Let's Encrypt automatiques)                       │
│  API FastAPI (Python)  ── SQLAlchemy 2 / Alembic ──►  PostgreSQL                      │
│     │  téléversement par morceaux, URL signées           ▲                           │
│     ▼                                                    │ file de tâches            │
│  Stockage fichiers (système de fichiers chiffré,         │ (Procrastinate, dans      │
│  puis SeaweedFS si besoin de plusieurs disques)          │  PostgreSQL)              │
│                                                          │                           │
│  Workers (conteneurs séparés, limités en CPU/mémoire) ───┘                           │
│   ├─ media    : vignettes, compression, extraction d'images clés (OpenCV, FFmpeg)    │
│   ├─ recon    : COLMAP / pycolmap (SfM), Open3D (nuage, maillage, mise à l'échelle)  │
│   ├─ render   : Blender en ligne de commande (Phase 3)                               │
│   └─ video    : FFmpeg LGPL (Phase 4)                                                │
│  Sauvegardes : pg_dump + copie des fichiers, chiffrées (restic), vers support séparé │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

**Choix de la file de tâches : Procrastinate (MIT), adossée à PostgreSQL.** Elle évite d'ajouter un courtier de messages. Redis est écarté (licence modifiée en 2024, puis option AGPL) ; si un cache ou un courtier devient nécessaire, Valkey (BSD-3) est l'alternative retenue.

**Choix du stockage : système de fichiers local en Phase 1.** MinIO est écarté (AGPL-3.0 et retrait progressif de l'édition communautaire). SeaweedFS (Apache-2.0) est l'option si le volume dépasse un disque.

## 3. Application mobile

### 3.1 Organisation du code

Organisation par fonctionnalité, chaque module isolé :

```
lib/
  app/            démarrage, thème, routeur, injection (Riverpod)
  core/           design system, formats (MAD, EUR, m²), erreurs, journal
  domain/         modèles et calculs purs : métrés, devis, mesures, unités
  data/
    local/        Drift : tables, DAO, migrations
    remote/       client API (dio), DTO
    sync/         file d'opérations, résolution de conflits
  features/
    auth/  dashboard/  projects/  scan/  metres/  plans/
    visualization/  estimates/  sites/  video/  client_space/
    library/  settings/
  l10n/           fichiers ARB (fr, puis ar avec RTL)
```

Règles : `domain/` n'importe ni Flutter ni réseau ; une fonctionnalité n'importe jamais l'intérieur d'une autre ; toute écriture passe par un dépôt (`repository`) qui écrit en local puis enfile l'opération.

### 3.2 Gestion d'état et navigation

- **Riverpod** (MIT) : dépendances testables, pas de singleton global. Remplace `provider` + `ChangeNotifier` monolithique de Qiyas.
- **go_router** (BSD-3) : routes déclaratives, redirections selon le rôle (un compte client ne peut pas atteindre une route collaborateur, même par lien profond). Cette garde est un confort ; la sécurité réelle est côté API.

### 3.3 Stockage local

- **Drift** sur SQLite (MIT). Le paquet `sqlite3_flutter_libs` est en fin de vie (version `0.6.0+eol` sur pub.dev) : le binaire SQLite est désormais fourni par le paquet `sqlite3` 3.x. À confirmer à l'intégration.
- Chiffrement de la base locale : **à examiner** (SQLCipher est sous licence BSD-like mais son intégration Flutter ajoute une dépendance native). En attendant, données dans le dossier privé de l'application, clé de session dans `flutter_secure_storage` (Keychain / Keystore).
- Médias : fichiers dans le dossier privé, référencés en base par identifiant ; compression à la capture (JPEG ≈ 2 500 px de grand côté, qualité 85) pour les photos de documentation, **pleine résolution conservée** pour les photos de scan.

### 3.4 Synchronisation

*Implémenté au lot 1.2 pour les fiches clients et projets (`lib/sync/sync_engine.dart`, `backend/app/routes/sync.py`).*

- Chaque enregistrement porte `id` (UUID v7, généré sur le téléphone), `version` (entier incrémenté par le serveur), `updated_at`, `deleted_at`, et `sync_seq`, numéro d'ordre attribué par un déclencheur PostgreSQL à chaque écriture.
- `sync_seq` est tiré sous un verrou transactionnel par organisation : l'ordre des numéros est l'ordre de validation, ce qui garantit qu'aucune écriture n'est sautée par un téléphone qui reprend « depuis le numéro N ».
- Le téléphone marque chaque fiche modifiée (`dirty`) avec la version serveur sur laquelle il s'est appuyé. Choix : synchronisation **par état** plutôt que par journal d'opérations (`sync_outbox`), plus simple et suffisante tant que seules des fiches entières sont échangées ; à réexaminer si des listes (lignes de devis) doivent être fusionnées champ par champ.
- Envoi : `POST /sync/push`, clients avant projets ; chaque fiche est appliquée ou refusée séparément (point de sauvegarde par fiche). Une `version de base` périmée → **conflit**. Réception : `GET /sync/pull?cursor=N`, suppressions comprises.
- Les fiches modifiées sur le téléphone ne sont envoyées que si le serveur les accepte ; un refus (donnée invalide, droit insuffisant) est affiché sur la fiche et n'est pas renvoyé en boucle.
- Un téléphone appartient au premier compte qui l'a synchronisé ; un autre compte ne peut pas synchroniser ses données (protection contre l'envoi de fiches sous une mauvaise identité).
- Un projet supprimé sur le serveur mais qui contient des pièces, photos ou devis présents uniquement sur le téléphone devient un conflit, jamais une suppression silencieuse.
- Un conflit n'est jamais résolu en silence pour une donnée métier (mesure, ligne de devis) : l'utilisateur choisit entre sa valeur et celle du serveur. Seules les données sans enjeu (préférences d'affichage) suivent « dernier écrit gagne ».
- Les fichiers sont envoyés par morceaux (reprise après coupure), après les métadonnées, en Wi-Fi par défaut pour les vidéos (paramétrable).
- Un devis **validé** ou **envoyé** est immuable : toute modification crée une nouvelle version.

### 3.5 Capture et contrôle qualité sur le téléphone

- Caméra : paquet `camera` (BSD-3) pour la capture guidée, `image_picker` pour l'import.
- Contrôle de netteté (variance du Laplacien), d'exposition (histogramme) et de recouvrement grossier entre photos successives : **en Dart pur sur une image réduite**, pour éviter d'embarquer OpenCV (le paquet `opencv_dart`, Apache-2.0, ajoute plusieurs dizaines de Mo). Décision à réévaluer en Phase 2 sur mesures réelles.
- Le téléphone ne prétend jamais calculer une dimension à partir d'une photo seule.

## 4. Serveur

### 4.1 API

- FastAPI, documentation OpenAPI générée automatiquement (`/docs` désactivé en production, schéma exporté dans le dépôt).
- Versionnement par préfixe `/api/v1`.
- Chaque requête est authentifiée, puis passe par une **dépendance d'autorisation** unique qui résout l'utilisateur, son organisation, son rôle et, pour un client, la liste de ses projets. Toutes les requêtes SQL métier sont construites à partir de ce contexte (pas de requête « nue »).
- PostgreSQL applique en plus une **sécurité au niveau des lignes (RLS)** sur `organization_id` pour les tables métier : défense en profondeur si un filtre applicatif est oublié.
- Erreurs normalisées (code, message en français compréhensible, identifiant de corrélation).

### 4.2 Traitements asynchrones

Les opérations lourdes créent une tâche (`jobs` gérée par Procrastinate, reflétée dans la table métier, ex. `scans.status`). Le téléphone consulte l'état (`en attente`, `en cours`, `terminé`, `échec` avec raison lisible). Les workers sont des conteneurs séparés, sans accès réseau sortant, avec limites mémoire, pour qu'une reconstruction ne bloque ni l'API ni la base.

### 4.3 Chaîne de reconstruction (Phase 2)

```
images / vidéo
  → tri (netteté, doublons, exposition)                    OpenCV
  → extraction d'images clés (vidéo)                       FFmpeg + OpenCV
  → Structure from Motion (poses + nuage épars)            COLMAP / pycolmap
  → [si GPU] stéréo multivue dense                         COLMAP (CUDA)
  → nettoyage, détection des plans (sol, murs, plafond)    Open3D (RANSAC)
  → mise à l'échelle par cote de référence                 Open3D
  → maillage, export PLY / OBJ / GLB                       Open3D
  → rapport de fiabilité                                   règles internes
```

**Rapport de fiabilité** obligatoire : nombre d'images recalées, erreur de reprojection moyenne, couverture estimée, cohérence de la cote de référence avec une seconde cote de contrôle. Si un seuil n'est pas atteint, le résultat est marqué **« non exploitable pour le métré »** et l'utilisateur est renvoyé vers la saisie manuelle. Les seuils seront fixés en Phase 2 sur des pièces mesurées indépendamment (au moins 10 pièces de typologies différentes).

### 4.4 Rendus et vidéo (Phases 3 et 4)

- Blender (GPL-2.0+) piloté en ligne de commande (`blender -b`) par des scripts Python dans un conteneur dédié. Utilisation côté serveur, sans distribution du binaire : pas d'obligation de redistribution du code source tant que Blender n'est pas distribué.
- Trois niveaux : aperçu (moteur EEVEE, faible résolution), détaillé, photoréaliste (Cycles). Chaque rendu est étiqueté « Simulation — non contractuelle ».
- Montage vidéo : FFmpeg compilé sans `--enable-gpl` ; codecs selon décision D-10.

## 5. Mesures : modèle de confiance

Chaque cote (`scan_measurements`) porte :

| Champ | Valeurs |
| --- | --- |
| `source` | `manual_tape`, `laser_meter`, `photogrammetry`, `ar_session`, `default_value` |
| `status` | `estimated` → `calibrated` → `verified` |
| `confidence` | 0–1, calculée selon la source et le rapport de fiabilité |
| `uncertainty_m` | incertitude estimée en mètres, si connue |

Règles :

- Une valeur par défaut (porte standard, hauteur standard) est `default_value` + `estimated` et s'affiche en orange.
- Un métré ne peut être **validé** que si toutes les cotes qui l'alimentent sont `verified`, ou si l'utilisateur confirme explicitement la liste des cotes non vérifiées (consigné dans `measurement_validations` et `audit_logs`).
- Un devis ne peut être **validé** que sur un métré validé.

## 6. Métrés et devis : règles de calcul

Reprises de Qiyas et étendues :

| Grandeur | Formule | Unité |
| --- | --- | --- |
| Surface de sol | aire du polygone de la pièce (formule du lacet) | m² |
| Périmètre | somme des longueurs de murs | m |
| Surface murale brute | Σ (longueur du mur × hauteur sous plafond) | m² |
| Surface murale nette | brute − Σ ouvertures du mur | m² |
| Plinthes | périmètre − Σ largeurs des portes | m |
| Volume | aire du sol × hauteur | m³ |
| Quantité à commander | quantité nette × (1 + taux de perte) | unité de l'ouvrage |

- Le taux de perte est un **paramètre de l'ouvrage** dans la bibliothèque (valeur par défaut **0 %**), affiché sur chaque ligne de métré quand il est non nul. Aucun coefficient implicite.
- Montants en **centimes entiers** (MAD ou EUR), arrondis ligne par ligne au centime, puis totaux. TVA paramétrable par organisation et surchargeable par ligne (plusieurs taux possibles sur un même devis).
- Prix de vente d'une ligne = (déboursé fournitures + déboursé main-d'œuvre) × (1 + frais indirects) × (1 + marge), ou prix de vente saisi directement ; la méthode est enregistrée sur la ligne.
- Un devis en EUR stocke le taux de change utilisé, sa date et sa source (saisie manuelle). Aucun taux n'est récupéré automatiquement depuis un service tiers.

## 7. Internationalisation

Français au démarrage. Textes externalisés en ARB dès la Phase 1 (`flutter gen-l10n`). Mise en page avec `EdgeInsetsDirectional` / `AlignmentDirectional` partout pour que l'arabe en RTL fonctionne sans refonte. PDF avec polices Noto Sans et Noto Sans Arabic (OFL-1.1) embarquées.

## 8. Design system

- Couleurs : `#151515` fond, `#222222` surfaces, `#F28C00` action principale, `#FF9D19` survol / accent, `#FFFFFF` texte, `#F2F2F2` fond clair, `#777777` texte secondaire. Contraste orange sur noir ≥ 4,5:1 vérifié avant figeage (Phase 1).
- Thème sombre par défaut (lisibilité extérieure à vérifier sur appareil : un thème clair à fort contraste est prévu pour le plein soleil).
- Cibles tactiles ≥ 48 dp, action principale en bas d'écran (usage à une main), texte de base ≥ 16 sp.
- Images d'arrière-plan : dix images (une par rubrique), voile noir ≥ 60 %, stockées dans `assets/backgrounds/` avec un fichier `CREDITS.md` (source, auteur, licence, URL de la page du fichier).
- Logo : uniquement le fichier original fourni, mis à l'échelle sans déformation.

## 9. Environnements et déploiement

| Environnement | Contenu |
| --- | --- |
| Développement | Docker Compose local, base jetable, données de test générées par les tests |
| Recette | Serveur LAMAALAM, données anonymisées ou fictives clairement marquées |
| Production | Serveur LAMAALAM, aucune donnée de démonstration |

CI (GitHub Actions, déjà en place) : analyse et tests Flutter, APK de test, tests Python (pytest), contrôle de licences des dépendances, migrations Alembic appliquées sur une base vierge. Le déploiement en production reste **manuel et déclenché par LAMAALAM** (script `deploy.sh` documenté dans `DEPLOYMENT.md`).

## 10. Ce qui n'est pas décidé

- Hébergement et matériel (D-04, D-06).
- Authentification (D-05) — l'architecture ci-dessus suppose l'option recommandée.
- Usage d'ARKit / ARCore (D-03).
- Chiffrement de la base SQLite locale.
- Codecs vidéo (D-10).
