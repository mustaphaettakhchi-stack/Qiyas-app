# Feuille de route — LAMAALAM

Version 0.1 — 1er novembre 2026 — statut : **PROPOSITION, à valider**

Règle de passage : une phase n'est close que lorsque ses critères de sortie sont atteints **sur de vrais chantiers**, testés par au moins un collaborateur de LAMAALAM qui n'a pas participé au développement. Aucune durée n'est garantie ; les estimations ci-dessous sont des ordres de grandeur pour un développement assisté par IA avec validation humaine régulière, et dépendent fortement des délais de réponse aux décisions.

## Phase 0 — Audit et conception (close le 1er novembre 2026, sauf D-06)

Livrables : `docs/PHASE0_DECISIONS.md`, `docs/ARCHITECTURE.md`, `docs/DATABASE_SCHEMA.md`, `OPEN_SOURCE_LICENSE_REGISTER.md`, `SECURITY.md`, `docs/ROADMAP.md`, `docs/USER_FLOWS.md`.

Sortie : réponses de LAMAALAM aux décisions bloquantes D-01, D-05, D-06, D-07, D-08.

## Phase 1 — MVP opérationnel

**État au 1er novembre 2026** :
- Lot 1.0 *partiel* : renommage, charte et logo, retrait des données de démonstration, serveur FastAPI + PostgreSQL + Alembic, Docker Compose, CI serveur. **Reste à faire** : Riverpod, go_router, Drift, ARB, contrôle automatique des licences dans la CI.
- Lot 1.1 *fait* : comptes, rôles, invitations, 2FA TOTP, codes de secours, sessions révocables, verrouillage, journal d'audit et lien de nouveau mot de passe créé par l'administrateur (serveur, 41 tests) ; écrans de connexion, mise en place de la 2FA, codes de secours, invitation, nouveau mot de passe, gestion de l'équipe (application) ; test de bout en bout application ↔ serveur réel. **Reste à faire** : effacement des données locales à la révocation ; envoi par e-mail du lien de nouveau mot de passe (aujourd'hui transmis par l'administrateur).
- Lot 1.2 *fait pour les fiches clients et projets* : tables `clients` et `projects` avec sécurité au niveau des lignes, références `LMA-AAAA-NNNN` attribuées par le serveur, synchronisation avec détection des conflits, écrans Clients et fiche projet complète (nature des travaux, type de bien, statut, budget, date de visite), consentement exigé avant les photos, reprise des projets Qiyas. Vérifié par 53 tests serveur et un test de bout en bout à deux téléphones (hors ligne, conflit, coupure réseau, refus, suppression). **Reste à faire** : pièces, photos et devis restent sur le téléphone (synchronisés aux lots 1.3 et 1.6) ; un collaborateur ne voit que les projets qu'il a créés ou dont il est responsable (pas encore d'équipe par projet) ; un projet retiré à un collaborateur reste sur son téléphone ; choix du responsable d'un projet depuis l'application (possible côté serveur seulement).

Ordre de développement (chaque lot est livré testé avant le suivant) :

| Lot | Contenu | Critère de sortie |
| --- | --- | --- |
| 1.0 Socle | Renommage, structure modulaire, Riverpod, go_router, Drift, design system LAMAALAM, ARB français, backend FastAPI + PostgreSQL + Alembic en Docker Compose, CI étendue (tests Python, contrôle de licences) | `flutter test`, `pytest` et migrations verts en CI ; écran « Licences » complet |
| 1.1 Authentification et utilisateurs | Comptes, rôles, invitations, 2FA, sessions révocables, journal d'audit | Tests d'isolation entre organisations et entre clients verts sur 100 % des routes |
| 1.2 Clients et projets | Fiches, référence unique, statuts, photos initiales, notes, recherche | Création complète d'un projet hors ligne puis synchronisée sans perte |
| 1.3 Relevé manuel | Étages, pièces **polygonales** (murs + angles), ouvertures par mur, origine et statut de chaque cote, alertes de cohérence (fermeture du polygone, plages de valeurs), photos par pièce | Écart nul entre métré calculé et calcul manuel indépendant sur 10 pièces réelles, dont 3 non rectangulaires |
| 1.4 Métrés | Sols, murs bruts/nets, plafonds, plinthes, volumes, menuiseries (comptage), électricité et plomberie (comptage manuel), coefficient de perte paramétrable affiché, traçabilité de chaque quantité, validation du métré | Cas de test partagés Dart/Python verts ; chaque quantité affiche sa formule |
| 1.5 Bibliothèque | Ouvrages, matériaux, fournisseurs, historique des prix, import CSV ; **démarre vide** | Aucun prix pré-rempli en production (test automatisé) |
| 1.6 Devis | Versions, statuts (brouillon, validé, envoyé, accepté, refusé), déboursés, frais indirects, marge, remise, TVA multi-taux, MAD/EUR avec taux saisi, numérotation serveur, PDF avec logo et polices Unicode | Un devis réel de LAMAALAM reproduit au centime près ; mentions légales validées par l'expert-comptable |
| 1.7 Tableau de bord | Indicateurs calculés depuis la base (chantiers actifs, prospects, devis en attente / acceptés, derniers projets, dernières opérations) | Chaque indicateur couvert par un test |
| 1.8 Espace client (lecture seule) | Projet, devis PDF envoyés, photos et étapes marquées visibles, messagerie simple | Test d'intrusion manuel « client A → données de B » négatif ; validation UX avec 2 clients réels |
| 1.9 Exploitation | Script de déploiement, sauvegarde, restauration testée, guides (`INSTALLATION.md`, `DEPLOYMENT.md`, `USER_GUIDE.md`, `DEVELOPER_GUIDE.md`, `BACKUP.md`, `RESTORE.md`, `TEST_REPORT.md`) | Restauration complète sur machine vierge réussie et chronométrée |

**Hors Phase 1** (volontairement) : scan, 3D, rendus, vidéo, acceptation en ligne des devis, factures (modèle prévu, écrans en Phase 5 après validation comptable).

Sortie de Phase 1 : deux semaines d'utilisation quotidienne réelle par LAMAALAM, avec au moins 5 devis réels produits par l'application, sans retour au tableur.

## Phase 2 — Scan et reconstruction

1. Capture guidée photo (contrôle de netteté, exposition, recouvrement, conseils de déplacement).
2. Capture vidéo et extraction d'images clés côté serveur.
3. Chaîne COLMAP (SfM) + Open3D (plans, échelle, maillage), sur CPU d'abord.
4. Rapport de fiabilité et seuils de rejet.
5. Mise à l'échelle par cote de référence + **cote de contrôle obligatoire** pour mesurer l'erreur réelle.
6. Report des dimensions estimées vers le relevé, statut « estimée », correction et validation manuelles.
7. Selon D-03 : module ARKit/ARCore optionnel.

Protocole de test : au moins 10 pièces mesurées indépendamment au télémètre laser (rectangulaires, en L, salle de bain carrelée, pièce aux murs blancs, couloir, façade). Publication des écarts mesurés dans `TEST_REPORT.md`. **Si l'écart médian dépasse un seuil fixé avec LAMAALAM (proposition : 2 % ou 5 cm), le scan reste un outil de documentation et n'alimente pas les métrés.**

## Phase 3 — Plans et visualisation

Plans 2D éditables (cloisons, ouvertures, mobilier), export PDF/PNG ; modèle 3D paramétrique généré depuis le relevé, export OBJ/PLY/GLB, visualisation `model_viewer_plus` ; matériaux et textures sous licence vérifiée ; rendus Blender à trois niveaux ; IA générative seulement après examen des modèles (D-11) et si un GPU est disponible (D-04). Étiquette « Simulation non contractuelle » sur chaque image.

## Phase 4 — Montage vidéo

Import et classement chronologique avant / pendant / après, gabarits 9:16, 1:1, 16:9, logo, titres, coordonnées, transitions, musique sous licence vérifiée, prévisualisation basse définition et validation avant export. Préalable : décision D-10.

## Phase 5 — Optimisation et distribution

Synchronisation avancée, notifications, factures et situations de travaux (après validation comptable), statistiques, arabe et RTL, audit de sécurité, tests sur appareils d'entrée de gamme, préparation des fiches store. **Aucune publication ni inscription payante sans accord explicite (D-09).**
