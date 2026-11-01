# Registre des licences Open Source — LAMAALAM

Version 0.2 — 1er novembre 2026 (ajouts du lot 1.1 : zxcvbn, cryptography, images Docker)

## Méthode de vérification

- **Paquets Dart/Flutter** : version et licence relevées le 1er novembre 2026 via l'API publique de pub.dev (`/api/packages/<nom>` et étiquettes `license:` de `/api/packages/<nom>/score`).
- **Paquets Python** : version et licence relevées le 1er novembre 2026 via l'API JSON de PyPI (`license_expression` ou classificateurs).
- **Logiciels hors registres** (COLMAP, Open3D, Blender, FFmpeg, OpenMVS, Valkey, SeaweedFS, Caddy, model-viewer, Depth Anything V2) : fichier `LICENSE`/`COPYING`/README lu sur la branche principale du dépôt officiel le 1er novembre 2026. **La version exacte n'a pas pu être relevée** (API GitHub inaccessible depuis l'environnement de travail) : elle sera figée et inscrite ici lors de l'intégration.
- **Non vérifié en ligne, d'après la connaissance de l'auteur** : PostgreSQL, Flutter/Dart, SQLite, Noto, Debian, Docker Engine, restic, OpenH264, Stable Diffusion XL, FLUX.1. Ces lignes portent la mention « (à re-vérifier) » et ne pourront passer au statut APPROUVÉ définitif qu'après lecture du texte de licence de la version installée.
- La version indiquée pour les paquets est la **dernière publiée** au jour du relevé ; la version effectivement utilisée sera celle du fichier de verrouillage (`pubspec.lock`, `requirements.lock`). Toute montée de version majeure impose de relire la licence.
- **Dépendances indirectes** : elles seront listées automatiquement par la CI à partir de la Phase 1 (`flutter pub deps`, `pip-licenses`) et toute licence hors liste blanche (MIT, BSD-2/3, Apache-2.0, ISC, Zlib, PSF, MPL-2.0, LGPL en liaison dynamique non modifiée, OFL-1.1, CC0, Unlicense, PostgreSQL) bloquera la construction.

Statuts : **APPROUVÉ** (intégrable) · **À EXAMINER** (suspendu, décision LAMAALAM ou avis juridique requis) · **REFUSÉ**.

> Rappel : Claude Code est l'outil de développement. Il n'est pas intégré au produit et ne figure pas dans ce registre.

## 1. Application mobile

| Composant | Dépôt officiel | Version relevée | Licence | Usage commercial | Obligations | Dépendances indirectes notables | Risques | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Flutter SDK / Dart (à re-vérifier) | github.com/flutter/flutter | ≥ 3.41.6 (exigée par le projet) | BSD-3-Clause | Oui | Conserver la notice de licence (écran « Licences » de l'app) | Skia, ICU, etc. (licences permissives, listées par `showLicensePage`) | Faible | APPROUVÉ |
| flutter_riverpod | github.com/rrousselGit/riverpod | 3.4.3 | MIT | Oui | Notice | riverpod | Faible | APPROUVÉ |
| provider (existant Qiyas, à retirer) | github.com/rrousselGit/provider | 6.1.5+1 | MIT | Oui | Notice | — | Faible | APPROUVÉ |
| go_router | github.com/flutter/packages | 18.1.2 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| drift | github.com/simolus3/drift | 2.35.3 | MIT | Oui | Notice | sqlite3 | Faible | APPROUVÉ |
| drift_dev (dév.) | github.com/simolus3/drift | 2.35.2 | MIT | Oui | — (non embarqué) | build_runner | Nul | APPROUVÉ |
| sqlite3 (Dart) | github.com/simolus3/sqlite3.dart | 3.8.0 | MIT (étiquette pub.dev) | Oui | Notice | Binaire SQLite (domaine public) | Faible | APPROUVÉ |
| sqlite3_flutter_libs | github.com/simolus3/sqlite3.dart | 0.6.0+eol | MIT | Oui | Notice | — | **Fin de vie** : ne pas utiliser | REFUSÉ (obsolète) |
| path_provider | github.com/flutter/packages | 2.1.6 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| camera | github.com/flutter/packages | 0.12.2 | BSD-3-Clause | Oui | Notice | CameraX (Android, Apache-2.0), AVFoundation (iOS, système) | Version < 1.0 : API instable | APPROUVÉ |
| image_picker | github.com/flutter/packages | 1.2.4 | Apache-2.0 / BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| video_player | github.com/flutter/packages | 2.14.1 | BSD-3-Clause | Oui | Notice | ExoPlayer/Media3 (Apache-2.0) | Faible | APPROUVÉ |
| flutter_image_compress | github.com/fluttercandies/flutter_image_compress | 2.5.1 | MIT | Oui | Notice | Bibliothèques natives à lister | Faible | APPROUVÉ |
| pdf | github.com/DavBfr/dart_pdf | 3.13.1 | Apache-2.0 | Oui | Notice, mention des modifications | — | Faible | APPROUVÉ |
| printing | github.com/DavBfr/dart_pdf | 5.15.1 | Apache-2.0 | Oui | Notice | PDFium sur certaines plateformes (BSD-3) | Faible | APPROUVÉ |
| share_plus | github.com/fluttercommunity/plus_plugins | 13.3.1 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| url_launcher | github.com/flutter/packages | 6.3.3 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| uuid | github.com/Daegalus/dart-uuid | 4.6.0 | MIT | Oui | Notice | crypto | Faible | APPROUVÉ |
| dio | github.com/cfug/dio | 5.11.1 | MIT | Oui | Notice | — | Faible | APPROUVÉ |
| flutter_secure_storage | github.com/mogol/flutter_secure_storage | 11.2.0 | BSD-3-Clause | Oui | Notice | Keychain / Keystore (système) | Faible | APPROUVÉ |
| connectivity_plus | github.com/fluttercommunity/plus_plugins | 7.3.2 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| workmanager | github.com/fluttercommunity/flutter_workmanager | 0.10.10 | MIT | Oui | Notice | WorkManager AndroidX (Apache-2.0) | Version < 1.0 ; comportement iOS limité par le système | APPROUVÉ |
| intl | github.com/dart-lang/i18n | 0.20.3 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| path, crypto (crypto : empreinte SHA-256 du métré validé, et calcul TOTP du test de bout en bout) | github.com/dart-lang/core | 1.9.1 / 3.0.8 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| json_annotation | github.com/google/json_serializable.dart | 4.12.0 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| freezed (dév.) | github.com/rrousselGit/freezed | 4.0.3 | MIT | Oui | — | — | Nul | APPROUVÉ |
| build_runner (dév.) | github.com/dart-lang/build | 2.17.1 | BSD-3-Clause | Oui | — | — | Nul | APPROUVÉ |
| mocktail (tests) | github.com/felangel/mocktail | 1.0.5 | MIT | Oui | — | — | Nul | APPROUVÉ |
| flutter_lints (dév.) | github.com/flutter/packages | 6.0.0 | BSD-3-Clause | Oui | — | — | Nul | APPROUVÉ |
| model_viewer_plus | github.com/omchiii/model_viewer_plus.dart | 1.10.0 | Apache-2.0 | Oui | Notice | `<model-viewer>` de Google (Apache-2.0, vérifié), three.js (MIT), WebView système | Rendu dans une WebView : performance à mesurer | APPROUVÉ (Phase 3) |
| file_picker (import de fichiers) | github.com/miguelpruivo/flutter_file_picker | 13.3.1 | **non affichée par pub.dev au 01/11/2026** | — | — | — | Licence non vérifiable : remplacé par le copier-coller du CSV | À EXAMINER (non intégré) |
| opencv_dart | github.com/rainyl/opencv_dart | 2.2.2 | Apache-2.0 | Oui | Notice | OpenCV natif (Apache-2.0) ; éventuels modules tiers à vérifier | Poids de l'app (plusieurs dizaines de Mo) | À EXAMINER (Phase 2, besoin non démontré) |
| Plugin ARKit / ARCore pour Flutter | à choisir | — | — | — | — | ARKit (Apple, propriétaire), Google Play Services for AR (propriétaire) | Composants propriétaires, voir D-03 | À EXAMINER |
| SQLCipher (chiffrement base locale) | github.com/sqlcipher/sqlcipher | — | BSD-3-Clause (édition communautaire, à re-vérifier) | Oui | Notice | OpenSSL / CommonCrypto | Intégration native | À EXAMINER |

## 2. Serveur

| Composant | Dépôt officiel | Version relevée | Licence | Usage commercial | Obligations | Dépendances indirectes notables | Risques | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Python (à re-vérifier) | github.com/python/cpython | 3.13 | PSF-2.0 | Oui | Notice | — | Faible | APPROUVÉ |
| FastAPI | github.com/fastapi/fastapi | 0.162.0 | MIT | Oui | Notice | Starlette (BSD-3), Pydantic | Version 0.x : changements possibles | APPROUVÉ |
| Uvicorn | github.com/Kludex/uvicorn | 0.54.0 | BSD-3-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| Pydantic / pydantic-settings | github.com/pydantic/pydantic | 2.14.2 / 2.16.2 | MIT | Oui | Notice | pydantic-core (MIT, Rust) | Faible | APPROUVÉ |
| SQLAlchemy | sqlalchemy.org | 2.1.6 | MIT | Oui | Notice | — | Faible | APPROUVÉ |
| Alembic | github.com/sqlalchemy/alembic | 1.20.1 | MIT | Oui | Notice | Mako (MIT) | Faible | APPROUVÉ |
| psycopg 3 (avec `psycopg[binary]`) | psycopg.org | 3.3.6 | LGPL-3.0-only | Oui | Utilisation non modifiée, en tant que bibliothèque : pas d'obligation sur notre code ; fournir la licence ; si modifiée, publier les modifications | libpq (PostgreSQL License) et OpenSSL embarqués par `psycopg-binary` | Faible si non modifiée et non redistribuée | APPROUVÉ (sans modification) |
| PostgreSQL (à re-vérifier) | postgresql.org | ≥ 16 | PostgreSQL License | Oui | Notice | — | Faible | APPROUVÉ |
| Procrastinate | github.com/procrastinate-org/procrastinate | 3.10.0 | MIT | Oui | Notice | psycopg | Faible | APPROUVÉ |
| argon2-cffi | github.com/hynek/argon2-cffi | 25.1.0 | MIT | Oui | Notice | argon2 de référence (CC0 / Apache-2.0) | Faible | APPROUVÉ |
| PyJWT | github.com/jpadilla/pyjwt | 2.15.1 | MIT | Oui | Notice | cryptography (Apache-2.0 / BSD) | Faible | APPROUVÉ |
| PyOTP | github.com/pyauth/pyotp | 2.10.0 | MIT | Oui | Notice | — | Faible | APPROUVÉ |
| cryptography | github.com/pyca/cryptography | 50.0.2 | Apache-2.0 OR BSD-3-Clause | Oui | Notice | OpenSSL embarqué dans les roues (Apache-2.0) | Faible | APPROUVÉ |
| zxcvbn (Python, contrôle de robustesse des mots de passe) | github.com/dwolfhub/zxcvbn-python | 4.5.0 | MIT | Oui | Notice | Listes de fréquence intégrées au paquet | Dernière publication en février 2025 : maintenance faible, à surveiller | APPROUVÉ |
| python-multipart | github.com/Kludex/python-multipart | 0.0.33 | Apache-2.0 | Oui | Notice | — | Faible | APPROUVÉ |
| Pillow (lot 1.8) | github.com/python-pillow/Pillow | 13.0.0 | MIT-CMU | Oui | Notice | libjpeg, libpng, zlib (roues PyPI) | Faible ; sert à produire la copie « client » des photos sans métadonnées (EXIF, GPS) | APPROUVÉ |
| email-validator | github.com/JoshData/python-email-validator | 2.3.0 | Unlicense | Oui | Aucune | dnspython (ISC) | Faible | APPROUVÉ |
| Jinja2 | github.com/pallets/jinja | 3.1.6 | BSD-3-Clause | Oui | Notice | MarkupSafe (BSD-3) | Faible | APPROUVÉ |
| structlog | github.com/hynek/structlog | 26.1.0 | MIT OR Apache-2.0 | Oui | Notice | — | Faible | APPROUVÉ |
| httpx (tests) | github.com/encode/httpx | 0.28.1 | BSD-3-Clause | Oui | — | — | Nul | APPROUVÉ |
| pytest / pytest-asyncio (tests) | github.com/pytest-dev | 9.2.0 / 1.4.1 | MIT / Apache-2.0 | Oui | — | — | Nul | APPROUVÉ |
| WeasyPrint (PDF côté serveur, si besoin) | github.com/Kozea/WeasyPrint | 70.0 | BSD-3-Clause | Oui | Notice | Pango, HarfBuzz (LGPL / MIT, bibliothèques système) | Faible | APPROUVÉ (optionnel) |
| Celery | github.com/celery/celery | 5.6.3 | BSD-3-Clause | Oui | Notice | Courtier requis | Ajoute un courtier ; non retenu | APPROUVÉ (non retenu) |
| Dramatiq | github.com/Bogdanp/dramatiq | 2.2.1 | LGPL-3.0+ | Oui | Comme psycopg | Courtier requis | Non retenu | APPROUVÉ (non retenu) |
| Redis ≥ 7.4 | github.com/redis/redis | — | RSALv2 / SSPLv1, puis option AGPLv3 (Redis 8) (à re-vérifier) | Restreint selon la licence choisie | Fortes | — | Changement de licence en 2024 | REFUSÉ |
| Valkey (alternative Redis) | github.com/valkey-io/valkey | à figer | BSD-3-Clause (vérifié) | Oui | Notice | — | Faible | APPROUVÉ (si besoin) |
| MinIO | github.com/minio/minio | — | AGPL-3.0 (à re-vérifier) | Oui avec obligations | Code source des modifications à fournir aux utilisateurs réseau | — | Édition communautaire réduite depuis 2025 | REFUSÉ |
| SeaweedFS | github.com/seaweedfs/seaweedfs | à figer | Apache-2.0 (vérifié) | Oui | Notice | — | Faible | APPROUVÉ (si besoin) |
| Caddy | github.com/caddyserver/caddy | à figer | Apache-2.0 (vérifié) | Oui | Notice | — | Faible | APPROUVÉ |
| Let's Encrypt (certificats) | letsencrypt.org | — | Service gratuit, accord d'abonné | Oui | Accepter l'accord d'abonné | — | Service externe gratuit (dépendance réseau au renouvellement) | APPROUVÉ |
| Docker Engine / Compose (à re-vérifier) | github.com/moby/moby, github.com/docker/compose | à figer | Apache-2.0 | Oui | Notice | — | **Docker Desktop est payant** pour les entreprises au-delà d'un seuil : n'utiliser que Docker Engine sur Linux | APPROUVÉ (Engine uniquement) |
| Debian (à re-vérifier) | debian.org | stable | Licences libres multiples (DFSG) | Oui | Selon paquets | — | Faible | APPROUVÉ |
| restic (sauvegardes) (à re-vérifier) | github.com/restic/restic | à figer | BSD-2-Clause | Oui | Notice | — | Faible | APPROUVÉ |
| Image Docker `postgres:16` | hub.docker.com/_/postgres | 16 | PostgreSQL License + paquets Debian | Oui | Notice | Debian | Image officielle, à épingler par empreinte avant la production | APPROUVÉ |
| Image Docker `python:3.13-slim` | hub.docker.com/_/python | 3.13 | PSF-2.0 + paquets Debian | Oui | Notice | Debian | Idem | APPROUVÉ |
| Image Docker `caddy:2` | hub.docker.com/_/caddy | 2 | Apache-2.0 | Oui | Notice | — | Idem | APPROUVÉ |
| age / age-keygen (outil d'exploitation, lot 1.9) (à re-vérifier) | github.com/FiloSottile/age | 1.1.1 (testée) | BSD-3-Clause | Oui | Notice | — (Go, binaire statique) | Faible ; installé sur le serveur et le poste du gérant, jamais distribué avec l'application | APPROUVÉ |

## 3. Vision par ordinateur, reconstruction, rendu, vidéo

| Composant | Dépôt officiel | Version relevée | Licence | Usage commercial | Obligations | Dépendances indirectes notables | Risques | Statut |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| OpenCV (opencv-python-headless) | github.com/opencv/opencv-python | 5.0.0.93 | Apache-2.0 | Oui | Notice | **Les roues PyPI embarquent FFmpeg (LGPL)** et d'autres bibliothèques | LGPL embarquée : acceptable côté serveur sans redistribution | APPROUVÉ |
| NumPy | numpy.org | 2.5.4 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 | Oui | Notice | OpenBLAS (BSD-3) | Faible | APPROUVÉ |
| Pillow | github.com/python-pillow/Pillow | 13.0.0 | MIT-CMU | Oui | Notice | libjpeg, libpng, etc. | Faible | APPROUVÉ |
| COLMAP | github.com/colmap/colmap | à figer (pycolmap 4.2.1 sur PyPI) | « new BSD » (BSD-3-Clause, vérifié) | Oui | Notice | Le fichier `LICENSE` précise que **certaines dépendances optionnelles peuvent modifier la licence du binaire** (ex. CGAL GPL/LGPL) ; CUDA pour le dense | Licence du binaire compilé à vérifier selon les options | APPROUVÉ (compilation sans dépendance GPL) |
| pycolmap | github.com/colmap/colmap | 4.2.1 | BSD-3-Clause | Oui | Notice | Roues PyPI **sans CUDA** : reconstruction dense indisponible | Faible | APPROUVÉ |
| NVIDIA CUDA / pilotes | developer.nvidia.com | — | Propriétaire (gratuit) | Oui selon CLUF | Respect du CLUF NVIDIA | — | Composant propriétaire, voir D-04 | À EXAMINER |
| OpenMVS | github.com/cdcseacave/openMVS | à figer | AGPL-3.0 (vérifié) | Oui avec obligations | Si modifié et offert par réseau : fournir le code source | — | AGPL ; utilisé non modifié en outil en ligne de commande, le risque est limité mais doit être validé | À EXAMINER |
| Open3D | github.com/isl-org/Open3D | 0.20.0 (PyPI) | MIT (vérifié) | Oui | Notice | Nombreuses dépendances tierces (listées dans le dépôt) | Faible | APPROUVÉ |
| Blender | github.com/blender/blender | LTS à figer | GPL-2.0-or-later (vérifié) | Oui | Obligations GPL **uniquement en cas de distribution** ; usage serveur interne sans distribution : aucune. Les fichiers produits (rendus, scènes) ne sont pas soumis à la GPL | Cycles (Apache-2.0) | Ne jamais distribuer Blender ni nos scripts liés à Blender avec l'application sans examen | APPROUVÉ (serveur uniquement) |
| FFmpeg (compilé sans `--enable-gpl`) | github.com/FFmpeg/FFmpeg | à figer | LGPL-2.1-or-later (vérifié) | Oui | Notice ; fournir le source de FFmpeg si distribué | Codecs : voir lignes suivantes | Brevets des formats | APPROUVÉ (build LGPL) |
| x264 (encodeur H.264) (à re-vérifier) | code.videolan.org/videolan/x264 | — | GPL-2.0-or-later (licence commerciale disponible) | Oui avec obligations GPL | Bascule FFmpeg en GPL | — | **Brevets H.264** | À EXAMINER (D-10) |
| OpenH264 (Cisco) (à re-vérifier) | github.com/cisco/openh264 | — | BSD-2-Clause | Oui | Notice | — | Couverture brevets Cisco limitée à son binaire officiel | À EXAMINER (D-10) |
| ffmpeg-python | github.com/kkroening/ffmpeg-python | 0.2.0 | Apache-2.0 | Oui | Notice | — | **Projet peu maintenu** ; préférer des appels `subprocess` directs | REFUSÉ (non nécessaire) |
| ffmpeg_kit_flutter (FFmpeg sur mobile) | — | — | LGPL/GPL selon variante | — | — | — | Projet retiré par son auteur ; vidéo traitée côté serveur | REFUSÉ |

## 4. Modèles d'intelligence artificielle (Phase 3, aucun n'est téléchargé à ce stade)

| Modèle | Source | Licence | Usage commercial | Risques | Statut |
| --- | --- | --- | --- | --- | --- |
| Depth Anything V2 Small | github.com/DepthAnything/Depth-Anything-V2 | Apache-2.0 (vérifié dans le README) | Oui | Profondeur relative, non métrique | APPROUVÉ (Phase 3) |
| Depth Anything V2 Base / Large / Giant | idem | CC-BY-NC-4.0 (vérifié dans le README) | **Non** | — | REFUSÉ |
| Segment Anything 2 (à re-vérifier) | github.com/facebookresearch/sam2 | Apache-2.0 | Oui | Vérifier la licence des poids, distincte du code | À EXAMINER |
| FLUX.1-schnell (à re-vérifier) | huggingface.co/black-forest-labs | Apache-2.0 | Oui | GPU ≥ 16 Go | À EXAMINER |
| FLUX.1-dev (à re-vérifier) | idem | Licence non commerciale | **Non** | — | REFUSÉ |
| Stable Diffusion XL base (à re-vérifier) | huggingface.co/stabilityai | CreativeML OpenRAIL++-M | Oui, avec restrictions d'usage à répercuter aux utilisateurs | Licence « responsable », pas Open Source au sens OSI | À EXAMINER |
| Modèles ControlNet | divers | variables selon le modèle | — | Chaque modèle à examiner | À EXAMINER |

## 5. Contenus (polices, images, musique)

| Composant | Source | Licence | Usage commercial | Obligations | Statut |
| --- | --- | --- | --- | --- | --- |
| Noto Sans, Noto Sans Arabic (Regular et Bold, embarquées pour le PDF du devis) | github.com/notofonts (fichiers de notofonts.github.io, relevés le 01/11/2026) | SIL OFL-1.1 (vérifié, `assets/fonts/OFL.txt`) | Oui | Ne pas vendre la police seule ; licence jointe dans `assets/fonts/` | APPROUVÉ |
| Logo Group LAMAALAM | Fourni par LAMAALAM le 01/11/2026 | Propriété de Group LAMAALAM (à confirmer, voir `assets/branding/README.md`) | — | Ne pas altérer sans instruction ; texte corrigé sur instruction | APPROUVÉ (réserves notées) |
| Police Arimo (outil : correction du texte du logo ; non embarquée) | github.com/googlefonts/arimo | relevée le 01/11/2026 sur github.com/google/fonts | SIL OFL-1.1 (vérifié, fichier OFL.txt) | Oui | Aucune pour une image produite avec la police ; conserver la licence si la police est redistribuée | — | Faible | APPROUVÉ |
| Photographies d'arrière-plan (10) | Wikimedia Commons / Openverse, **fichier par fichier** | CC0, domaine public ou CC BY (à préférer) ; CC BY-SA acceptable avec attribution et partage à l'identique du fichier dérivé | Oui | Attribution dans l'écran « Crédits » et `assets/backgrounds/CREDITS.md` | À EXAMINER (sélection en Phase 1) |
| Images Unsplash / Pexels | — | Licences propres, non Open Source, restrictions (pas de compilation, pas de revente) | Ambigu | — | REFUSÉ |
| Licences CC « NC » ou « ND » | — | Non commercial / pas de modification | **Non** | — | REFUSÉ |
| Musique des montages vidéo | à constituer (Phase 4) | CC0 ou CC BY uniquement, droits commerciaux vérifiés morceau par morceau | — | Attribution | À EXAMINER (Phase 4) |

## 6. Composants propriétaires utilisés uniquement pour développer ou construire

Ces outils ne sont pas intégrés au produit distribué mais sont listés par transparence.

| Outil | Rôle | Licence | Statut |
| --- | --- | --- | --- |
| Claude Code | Agent de développement | Propriétaire (Anthropic) | Outil de développement uniquement (§2) |
| GitHub / GitHub Actions | Hébergement du code, CI | Service propriétaire (offre gratuite) | Déjà en place, à confirmer par LAMAALAM |
| Xcode / macOS | Compilation iOS (obligatoire) | Propriétaire Apple, gratuit | À EXAMINER (D-09) |
| Android SDK / Gradle | Compilation Android | Apache-2.0 (SDK sous conditions Google) | APPROUVÉ |
