# Phase 0 — Audit, risques et décisions à valider par Groupe LAMAALAM

Version 0.2 — 1er novembre 2026 — statut : **Phase 0 close pour les décisions bloquantes ; D-06 en attente**

Ce document est la porte d'entrée de la Phase 0. Il recense ce qui existe, ce qui pose problème dans le cahier des charges, et les décisions que seul Groupe LAMAALAM peut prendre. **Aucun développement de la Phase 1 ne démarre avant réponse aux décisions marquées « bloquante ».**

Livrables associés :

| Livrable | Emplacement |
| --- | --- |
| Architecture | [`docs/ARCHITECTURE.md`](ARCHITECTURE.md) |
| Schéma de données | [`docs/DATABASE_SCHEMA.md`](DATABASE_SCHEMA.md) |
| Registre des licences | [`OPEN_SOURCE_LICENSE_REGISTER.md`](../OPEN_SOURCE_LICENSE_REGISTER.md) |
| Sécurité | [`SECURITY.md`](../SECURITY.md) |
| Feuille de route | [`docs/ROADMAP.md`](ROADMAP.md) |
| Parcours utilisateurs et critères d'acceptation | [`docs/USER_FLOWS.md`](USER_FLOWS.md) |

---

## 1. Audit de l'existant

Le dépôt contient déjà un MVP Flutter nommé **Qiyas** (≈ 3 500 lignes) : relevé de pièces rectangulaires, métré, grille de prix, devis PDF en MAD, partage WhatsApp. Il est **local uniquement** (fichier JSON sur le téléphone).

### Ce qui est réutilisable

| Élément | Fichier | Verdict |
| --- | --- | --- |
| Règles de calcul (périmètre, sols, murs nets, plinthes, volume, totaux en centimes) | `lib/domain/calculations.dart` | **Réutilisable**. Fonctions pures, testées (`test/calculations_test.dart`). Calculs en entiers pour les montants : bonne pratique à conserver. |
| Génération PDF hors connexion | `lib/services/pdf_service.dart` | Réutilisable, mais la police intégrée ne couvre pas l'arabe (déjà signalé dans le README). |
| Écrans de saisie pièce, plan, métré, devis | `lib/ui/screens/*` | Réutilisables comme base d'ergonomie, à adapter à la charte LAMAALAM. |
| CI GitHub Actions (analyse, tests, APK) | `.github/workflows/ci.yml` | Réutilisable. |

### Ce qui est incompatible avec le cahier des charges LAMAALAM

| Constat | Exigence violée | Conséquence |
| --- | --- | --- |
| Connexion par code SMS **fixe** `482913` (`FakeSmsAuthService`) | §9 Authentification sécurisée | À supprimer. Un vrai SMS exige un fournisseur payant → voir décision D-05. |
| Données d'exemple chargées au premier lancement, avec prix inventés (`sample_data.dart` : carrelage 280 MAD/m², etc.) | §7 « Ne jamais inventer un prix », §13 « pas de données de démonstration en production » | À cantonner aux tests. La production démarre avec une bibliothèque de prix **vide**. |
| Stockage JSON monolithique, pas de serveur | §5, §7, §10 (espace client, contrôle d'accès serveur) | Couche de données à réécrire (SQLite local + API + synchronisation). |
| Pièces exclusivement rectangulaires (L × l) | §3 Mesures, §4 Métrés | Inexploitable pour une pièce en L, un couloir coudé, un mur biais. Le modèle doit passer à un **polygone** de murs. |
| Ouvertures aux dimensions standard (0,83 × 2,04) appliquées par défaut | §4 « Ne jamais appliquer automatiquement un coefficient universel sans l'indiquer » | Acceptable uniquement si la valeur est affichée comme **valeur par défaut non vérifiée**. |
| Pas de notion d'origine ni de confiance de mesure | §3 Contrôle des dimensions | À ajouter dans le modèle (estimée / calibrée / vérifiée). |
| Pas de coefficient de perte, pas de déboursé ni de marge | §4, §7 | À ajouter. |
| Statuts de devis : brouillon, envoyé, accepté, refusé | §7 demande aussi « validé » | Statut à ajouter. |
| Fichier `assets/branding/logo_lamaalam_original.png` | §4 | **Absent du dépôt.** Voir D-07. |

**Recommandation** : faire évoluer ce dépôt plutôt que repartir de zéro (gain estimé : le moteur de calcul et le PDF), mais en considérant que ≈ 70 % du code (données, authentification, état) sera remplacé. Voir D-01.

---

## 2. Points du cahier des charges que je conteste

Je les signale parce qu'ils engagent la fiabilité du produit, conformément au principe directeur.

1. **Précision du scan sans capteur de profondeur.** Le cahier des charges exige de ne pas imposer le LiDAR (§12) *et* de produire des métrés fiables (§4). Avec une photogrammétrie monoculaire mise à l'échelle par une seule cote de référence, l'erreur d'échelle typique est de l'ordre de **plusieurs pourcents** et peut être bien pire sur des murs blancs peu texturés (cas très fréquent en rénovation). Sur un mur de 5 m, 3 % = 15 cm. **Conclusion : le scan ne remplacera pas le mètre laser pour les métrés facturés.** Il servira à la documentation, au plan indicatif et à la détection d'oubli. Le parcours « mesures manuelles assistées » est le parcours principal, pas le parcours de secours. Je recommande l'achat d'un télémètre laser (Bluetooth ou non) par collaborateur — c'est une dépense, donc soumise à votre accord (D-02).
2. **ARKit / ARCore.** Ce sont les seules briques qui donnent une échelle métrique fiable sur smartphone (suivi inertiel, détection de plans, LiDAR quand il existe). ARKit fait partie d'iOS ; ARCore repose sur les « Google Play Services for AR », composant propriétaire de Google. Ils sont gratuits mais **non Open Source** : leur usage tombe sous la règle §2 et requiert votre décision (D-03).
3. **Reconstruction dense COLMAP.** La partie dense (MVS) de COLMAP **exige une carte graphique NVIDIA et CUDA**, dont les pilotes et la boîte à outils sont propriétaires (gratuits). L'alternative Open Source OpenMVS est sous **AGPL-3.0**. Il faut un serveur avec GPU : c'est une dépense matérielle (D-04).
4. **Table `3d_models`.** Un identifiant PostgreSQL ne peut pas commencer par un chiffre sans guillemets, source d'erreurs dans tous les outils. Elle est renommée `models_3d` dans le schéma.
5. **Montage vidéo et H.264.** Le format attendu par TikTok / Reels / Facebook est en pratique le MP4 H.264. L'encodeur libre de référence (x264) est sous **GPL** et le format H.264 est couvert par des **brevets** dont la licence commerciale relève d'un pool (Via LA). L'usage côté serveur interne ne déclenche pas la GPL, mais le risque brevet doit être examiné (D-10).
6. **IA générative (Menu 6).** Les modèles d'image les plus connus ne sont pas « Open Source » au sens strict : Stable Diffusion XL (licence OpenRAIL++-M, restrictions d'usage), FLUX.1-dev (**non commercial, refusé**), Depth Anything V2 Base/Large (**CC-BY-NC-4.0, refusé** ; seul le modèle *Small* est sous Apache-2.0, vérifié dans le README officiel). Il faut un GPU d'au moins 12–16 Go de mémoire pour un rendu raisonnable. Ce module est repoussé à la Phase 3 et ne doit pas conditionner le MVP.
7. **Phase 1 trop large pour « usage quotidien rapide ».** L'espace client (Menu 10) suppose un serveur exposé sur Internet, une authentification des clients, un hébergement, HTTPS, des sauvegardes. Je le maintiens en Phase 1 comme demandé, mais en **lecture seule** (consultation projet, devis PDF, photos autorisées). L'acceptation en ligne d'un devis est repoussée (pas de signature électronique conforme à la loi 53-05 disponible).
8. **Images d'arrière-plan sur chaque rubrique.** Compatible avec la sobriété demandée à condition d'un voile sombre fort (≥ 60 %) et d'images compressées (≤ 150 Ko chacune) ; sinon contraste et poids de l'APK se dégradent. Elles ne peuvent pas être téléchargées depuis cet environnement (Wikimedia Commons inaccessible) : la sélection sera faite en Phase 1, image par image, avec licence vérifiée sur la page du fichier.
9. **Ce que je n'ai pas pu vérifier.** Le cadre fiscal (taux de TVA applicables aux travaux, facturation électronique DGI), les mentions obligatoires d'un devis au Maroc et les formalités CNDP relèvent d'un expert-comptable et d'un juriste. Les écrans les rendront paramétrables ; je ne fixe aucun taux en dur.

---

## 3. Décisions à prendre par Groupe LAMAALAM

Format imposé par §15 : besoin, solution, licence, alternatives, coût, conséquence d'un refus.

| # | Sujet | Bloquante pour | Recommandation |
| --- | --- | --- | --- |
| D-01 | Faire évoluer le dépôt Qiyas existant ou repartir à zéro | Phase 1 | Faire évoluer, renommer l'application en LAMAALAM |
| D-02 | Télémètre laser pour les collaborateurs | Phase 1 (fiabilité) | Accepter, 1 appareil par collaborateur |
| D-03 | ARKit / ARCore (frameworks propriétaires gratuits) | Phase 2 | Accepter en option, jamais obligatoire |
| D-04 | Serveur de calcul avec GPU NVIDIA | Phase 2 | Différer l'achat après un essai sur CPU |
| D-05 | Mode d'authentification (SMS payant ou e-mail) | **Phase 1** | E-mail + mot de passe + 2FA TOTP, aucun SMS |
| D-06 | Hébergement du serveur (lieu, matériel) | **Phase 1** | Serveur au Maroc, géré par LAMAALAM |
| D-07 | Fourniture du logo original | **Phase 1** | Fournir le PNG haute définition (et le vectoriel s'il existe) |
| D-08 | Envoi d'e-mails (invitations, réinitialisation) | **Phase 1** | Utiliser le compte de messagerie existant de l'entreprise en SMTP |
| D-09 | Comptes développeur Apple / Google | Distribution | Ne rien engager avant la fin de Phase 1 |
| D-10 | Encodage vidéo H.264 (brevets) | Phase 4 | Examen juridique avant Phase 4 |
| D-11 | Modèles d'IA générative | Phase 3 | Examen au cas par cas |

### D-01 — Base de code

- **Besoin** : démarrer le MVP sans perdre le travail existant.
- **Solution** : conserver `calculations.dart`, `pdf_service.dart`, la CI et l'ergonomie des écrans ; réécrire données, authentification, état et navigation ; renommer le paquet (`qiyas` → `lamaalam`).
- **Licence / coût** : sans objet.
- **Alternative** : nouveau dépôt vierge.
- **Si refus** : +1 à 2 semaines pour réécrire calculs, tests et PDF.
- **Question** : Qiyas et LAMAALAM sont-ils le même produit (renommage) ou deux produits distincts qui doivent coexister ?

### D-02 — Télémètre laser

- **Besoin** : métrés facturables fiables (≈ ±2 mm).
- **Solution** : saisie manuelle assistée dès la Phase 1 ; connexion Bluetooth en option ultérieure (le protocole dépend du modèle, souvent non documenté publiquement).
- **Licence** : sans objet (matériel).
- **Coût** : achat d'appareils, à chiffrer par vos soins.
- **Alternative** : mètre ruban (plus lent, erreurs de lecture).
- **Si refus** : l'application fonctionne, mais la qualité des métrés dépend uniquement de la saisie.

### D-03 — ARKit / ARCore

- **Besoin** : échelle métrique fiable et guidage de capture en temps réel.
- **Solution** : module optionnel activé seulement si l'appareil le supporte ; le parcours photo/vidéo pur reste disponible.
- **Licence** : ARKit = framework Apple propriétaire inclus dans iOS ; ARCore = SDK sous Apache-2.0 mais moteur « Google Play Services for AR » propriétaire. Le plugin Flutter qui les relie devra lui-même être examiné.
- **Coût** : gratuit.
- **Alternative Open Source** : photogrammétrie COLMAP + cote de référence (précision inférieure, traitement différé).
- **Si refus** : le scan reste purement différé (résultat après envoi au serveur) et indicatif.

### D-04 — Serveur GPU

- **Besoin** : reconstruction dense, maillage texturé, rendus Blender Cycles, IA générative.
- **Solution** : phase 2 démarrée sur CPU (reconstruction éparse COLMAP/pycolmap, que les paquets PyPI fournissent sans CUDA) ; achat ou location d'un GPU uniquement si les essais sur pièces réelles le justifient.
- **Licence** : pilotes NVIDIA et CUDA propriétaires (gratuits, licence d'utilisation NVIDIA).
- **Coût** : matériel ou location, à chiffrer.
- **Alternative** : OpenMVS sur CPU (AGPL-3.0, lent).
- **Si refus** : pas de maillage texturé fiable ; nuage de points épars et plan indicatif uniquement.

### D-05 — Authentification

- **Besoin** : connexion sécurisée des administrateurs, collaborateurs et clients.
- **Solution recommandée** : identifiant e-mail + mot de passe haché (Argon2id) + double authentification TOTP (application d'authentification libre, ex. Aegis / FreeOTP) obligatoire pour administrateurs et collaborateurs ; clients invités par lien à usage unique.
- **Licence** : argon2-cffi (MIT), PyOTP (MIT).
- **Coût** : nul.
- **Alternative** : SMS (nécessite un fournisseur payant → contraire à §15 sans accord), ou connexion par lien WhatsApp (API WhatsApp Business payante et propriétaire → refusée).
- **Si refus de l'e-mail** : il faut choisir et payer un fournisseur SMS.

### D-06 — Hébergement

- **Besoin** : API, base PostgreSQL, fichiers (photos, vidéos, scans), espace client accessible par Internet.
- **Solution** : un serveur Linux (Debian stable) au Maroc, sous contrôle de LAMAALAM, avec Docker Compose ; sauvegardes chiffrées vers un second support physique distinct.
- **Points juridiques** : un hébergement hors du Maroc (ex. Union européenne) implique un transfert international de données personnelles soumis à la loi 09-08 et aux formalités CNDP.
- **Coût** : matériel ou location d'un serveur dédié, nom de domaine, connexion. **Aucun engagement de ma part.**
- **Si refus** : l'application fonctionne en local uniquement, sans espace client ni partage multi-appareils.

### D-07 — Logo

Le fichier `assets/branding/logo_lamaalam_original.png` n'existe pas dans le dépôt. Je ne redessinerai pas le logo. Merci de fournir le fichier original (PNG ≥ 1024 px de large, fond transparent si possible, et le fichier vectoriel SVG/PDF/AI s'il existe), ainsi que la confirmation que Groupe LAMAALAM en détient les droits.

### D-08 — Envoi d'e-mails

Un serveur de messagerie auto-hébergé est réputé mal délivré (filtres anti-spam). Recommandation : relais SMTP du compte de messagerie professionnel existant de l'entreprise. Si aucun compte n'existe, c'est une dépense à décider.

### D-09 — Distribution

Google Play (frais d'inscription unique) et Apple App Store (abonnement annuel au programme développeur) sont payants. Pendant la Phase 1, distribution par APK Android de test (déjà produit par la CI) et compilation iOS locale sur un Mac de l'entreprise. **Pas d'iPhone de test sans Mac** : la compilation iOS exige macOS et Xcode (gratuit, propriétaire Apple, environnement de développement uniquement).

### D-10 — Vidéo

FFmpeg compilé **sans** `--enable-gpl` reste sous LGPL-2.1+. L'encodeur H.264 libx264 force la GPL et le format H.264 est soumis à brevets. Options à examiner : (a) FFmpeg LGPL + OpenH264 de Cisco (BSD-2, avec la particularité que la couverture brevets de Cisco ne vaut que pour son binaire officiel) ; (b) VP9/AV1 libres de redevances mais moins bien acceptés par les réseaux sociaux ; (c) x264 côté serveur uniquement après avis juridique.

### D-11 — IA générative

Chaque modèle sera inscrit au registre avant tout téléchargement. Retenus pour examen : FLUX.1-schnell (Apache-2.0), SDXL base (OpenRAIL++-M, À EXAMINER), Segment Anything 2 (Apache-2.0), Depth Anything V2 Small (Apache-2.0). Refusés : FLUX.1-dev, Depth Anything V2 Base/Large/Giant (non commerciaux).

---

## 4. Risques principaux

| Risque | Probabilité | Impact | Parade |
| --- | --- | --- | --- |
| Précision du scan insuffisante pour facturer | Élevée | Élevé | Mesure manuelle = référence ; scan = indicatif ; origine de chaque cote affichée |
| Périmètre trop large (12 menus, 5 phases) | Élevée | Élevé | Phase 1 limitée au parcours visite → devis ; chaque phase validée sur chantier réel avant la suivante |
| Serveur unique = point de défaillance | Moyenne | Élevé | Mode hors ligne, sauvegardes testées par restauration mensuelle |
| Conflits de synchronisation (deux collaborateurs sur un même projet) | Moyenne | Moyen | Versionnement par enregistrement, conflit présenté à l'utilisateur, jamais écrasé en silence |
| Licence d'une dépendance indirecte incompatible | Moyenne | Élevé | Contrôle automatisé des licences dans la CI (Phase 1) |
| Fuite de données client (photos de domiciles) | Faible | Très élevé | Isolation par organisation et par client côté serveur, URL de fichiers signées et expirantes, tests d'autorisation systématiques |
| Mentions fiscales du devis erronées | Moyenne | Élevé | Validation par un expert-comptable avant usage commercial |
| Appareils Android d'entrée de gamme | Élevée | Moyen | Compression à la capture, traitement lourd sur le serveur, tests sur appareil 3 Go de RAM |

---

## 5. Décisions reçues le 1er novembre 2026

| # | Réponse de Groupe LAMAALAM | Conséquence appliquée | Réserves |
| --- | --- | --- | --- |
| D-01 | Faire évoluer Qiyas et le remplacer | Paquet renommé `lamaalam`, application « LAMAALAM ». Données d'exemple et prix inventés retirés de l'application (conservés uniquement pour les tests). Les données d'une ancienne installation Qiyas sont reprises au premier lancement. | — |
| D-05 | Double authentification acceptée | E-mail + mot de passe (Argon2id) + TOTP obligatoire pour administrateurs et collaborateurs, codes de secours, comptes par invitation : implémenté côté serveur et dans l'application (lot 1.1). La connexion de démonstration Qiyas est supprimée. | Sans serveur hébergé (D-06), seule la version « démonstration sans serveur » est utilisable sur le terrain. |
| D-06 | Hostinger envisagé, **non validé** | Aucun engagement, aucun compte créé. La pile reste portable (Docker Compose) et se développe en local. | Voir ci-dessous. |
| D-07 | Logo fourni, puis remplacé le même jour par un second fichier « à utiliser », **numéro de téléphone à supprimer** | Second fichier stocké sans modification ; variante sans numéro obtenue par simple recadrage ; maquette 3D retirée. | Réserves dans `assets/branding/README.md`, dont **l'orthographe « lamaalm »** du logo et sa résolution insuffisante pour l'impression. |
| D-08 | Compte provisoire Gmail (adresse de contact de l'entreprise) | Relais SMTP configurable par variables d'environnement, jamais dans le code ; sans configuration, le lien d'invitation est affiché à l'administrateur. | Voir ci-dessous. |

### Réserves sur Hostinger (D-06)

- **Type d'offre.** Seul un **VPS** (serveur virtuel avec accès root) peut faire tourner Docker, PostgreSQL et les traitements. Les offres d'hébergement web mutualisé ou « cloud » de Hostinger ne le permettent pas.
- **Localisation.** À ma connaissance, Hostinger n'a pas de centre de données au Maroc (à vérifier au moment de la commande). Les données personnelles des clients seraient donc **transférées hors du Maroc** : régime de transfert de la loi 09-08, à traiter avec la CNDP **avant** la mise en production.
- **Pas de GPU.** Les VPS standard n'ont pas de carte graphique : suffisant pour les phases 1 et 4, insuffisant pour la reconstruction dense et les rendus photoréalistes (D-04).
- **Coût.** C'est un service payant : il ne sera souscrit que sur votre décision explicite. La pile n'utilise aucun service propre à Hostinger, ce qui garantit qu'on pourra changer d'hébergeur sans réécriture.

### Réserves sur Gmail (D-08)

- Le compte doit avoir la **validation en deux étapes Google activée** et un **mot de passe d'application** dédié ; ce mot de passe ne doit être stocké que dans le fichier `.env` du serveur.
- Gmail grand public limite le volume d'envoi quotidien et n'est pas conçu pour les envois applicatifs : suffisant pour des invitations, pas pour des notifications en masse.
- Gmail est un service propriétaire (gratuit) : acceptable comme solution **provisoire**, à remplacer par la messagerie du nom de domaine de l'entreprise lorsqu'elle existera.

### Décisions restant ouvertes

D-02 (télémètre), D-03 (ARKit/ARCore), D-04 (GPU), D-06 (hébergement), D-09 (comptes stores), D-10 (vidéo), D-11 (modèles d'IA). Aucune ne bloque la suite de la Phase 1, sauf D-06 pour la mise en service de l'espace client.

### Nouveaux constats

- **Contraste de la palette.** Texte blanc sur orange #F28C00 : 2,46:1, soit moins que le minimum WCAG AA de 4,5:1. L'application utilise donc du **texte noir sur les boutons orange** (7,41:1). Le gris technique #777777 n'atteint que 4,08:1 sur #151515 : il est réservé aux bordures, et le texte secondaire utilise #B3B3B3 (8,71:1). **Écart validé par Groupe LAMAALAM le 1er novembre 2026.**
- **Fausses informations retirées de Qiyas** : l'indicateur « Synchronisé » s'affichait alors qu'aucune donnée ne quittait le téléphone, et l'écran de connexion affirmait un traitement « déclaré à la CNDP ». Les deux sont supprimés. De même, le bouton « télémètre simulé » injectait dans les cotes une valeur aléatoire à ±3 % : il est masqué tant qu'aucun appareil réel n'est branché.
