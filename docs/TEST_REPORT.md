# Rapport de tests — Phase 1 (lots 1.0 à 1.9)

État au 1er novembre 2026, branche `ccr-83d84652-2mby05`. Chaque envoi sur la branche relance l'ensemble dans la CI GitHub Actions ; un seul échec bloque.

## 1. Synthèse

| Suite | Nombre | Résultat | Où |
| --- | --- | --- | --- |
| Tests serveur (PostgreSQL réel, rôle **sans** superutilisateur : la sécurité au niveau des lignes est réellement exercée) | 99 | réussis | CI `serveur` + poste de développement |
| Cohérence modèles ↔ migrations (`alembic check`) et aller-retour des migrations | 9 migrations | réussi | CI `serveur` ; aller-retour 0006 → 0009 → 0006 → 0009 vérifié **sur une base remplie** |
| Tests de l'application (calculs, écrans sur téléphone 360 × 740 points, session, synchronisation, espace client, restauration) | 77 | réussis | CI `verifier-et-construire` |
| Scénarios de bout en bout application ↔ vrai serveur | 5 | réussis | CI `bout-en-bout` |
| Exercice de restauration complète sur machine vierge (pile Docker de production) | 1 | réussi | CI `exploitation` + poste de développement |
| Construction des APK Android de test | 2 | réussie | CI `verifier-et-construire` |

## 2. Couverture par lot

| Lot | Vérifié automatiquement | Reste à vérifier par Group LAMAALAM (critère de sortie) |
| --- | --- | --- |
| 1.1 Comptes | Invitation seule voie d'accès, mots de passe forts (zxcvbn), double authentification avec refus du rejeu, codes de secours, verrouillage, rotation des jetons avec détection de réutilisation, révocation, journal d'audit, isolement entre organisations, aucune route ouverte par erreur | — |
| 1.2 Clients, projets | Synchronisation, conflits, coupure réseau, refus, suppression, références `LMA-AAAA-NNNN` | — |
| 1.3 Relevé | Formes quelconques, fermeture (2 cm), angles, croisements ; mêmes calculs application/serveur (`shared/metre_cases.json`) | **Essai sur 10 pièces réelles** mesurées indépendamment |
| 1.4 Métré | Métré par lot et par pièce, perte, validation, empreinte « à revalider » | — |
| 1.5 Bibliothèque | Droits (administrateur seul), prix d'achat jamais transmis aux collaborateurs, historique en insertion seule, import CSV tout ou rien | — |
| 1.6 Devis | Cycle de vie, numérotation serveur, devis figé (API **et** déclencheur PostgreSQL), TVA par taux, remise, MAD/EUR, montants au centime (`shared/quote_cases.json`), PDF Unicode (nom arabe vérifié sur rendu), aucun déboursé ni marge dans le PDF | **Mentions légales et taux de TVA par l'expert-comptable** ; reproduction d'un devis réel au centime |
| 1.7 Tableau de bord | Chaque indicateur ; indicateurs du téléphone identiques à ceux du serveur | — |
| 1.8 Espace client | Client A ne voit rien du client B ni d'une autre organisation (404 partout), rien de non partagé, liens signés de 15 minutes (expiré 410, modifié 403), copie client sans GPS, messagerie, compteur de non-lus | **Test d'intrusion manuel « client A → données de B »** ; essai avec 2 clients réels |
| 1.9 Exploitation | Installation, sauvegarde chiffrée (illisible sans la clé privée), destruction complète, restauration, connexion avec le **même** secret de double authentification, fichier identique octet pour octet, journal ; mauvaise clé refusée sans rien arrêter ; téléphones : restauration détectée avant tout envoi, aucune fiche écrasée par une version plus ancienne, fiches inconnues renvoyées, numéros réservés | Exercice mensuel sur machine d'essai ; **restauration trimestrielle de la vraie archive avec la vraie clé** (une fois un serveur en service) |

## 3. Restauration : temps mesurés

| Mesure | Durée | Conditions |
| --- | --- | --- |
| Restauration, poste de développement | 17 s | image Docker en cache |
| Restauration, machine GitHub neuve | 13 s | image construite plus tôt dans le même exercice (cache de construction encore présent) |
| Restauration, machine vierge **sans aucun cache** | **31 s** | CI, exécution n° 11 (commit 987ff79) : images PostgreSQL et Caddy téléchargées, image de l'API entièrement reconstruite (8,6 s d'installation des dépendances), base et fichiers restaurés, migrations, démarrage |

L'exercice crée volontairement peu de données. Le temps réel augmente avec le volume des photos et de la base ; il sera mesuré sur la première vraie archive.

## 4. Défauts trouvés par les tests pendant la phase 1 (tous corrigés)

- **Migration 0007** : sur toute base contenant déjà une invitation client, la pose des clés étrangères échouait, parce que la RLS forcée masquait les fiches clients au propriétaire. Trouvé par l'aller-retour des migrations sur une base remplie.
- **Pile Docker** : l'API, en lecture seule, n'avait aucun volume pour les fichiers. En production, tout envoi de photo ou de PDF aurait échoué. Trouvé en préparant le lot 1.9.
- **Restauration** : sans protection, un téléphone aurait :
  - ignoré les nouvelles modifications (curseur en avance sur le serveur restauré) ;
  - écrasé sans le dire le travail fait après la sauvegarde ;
  - et un numéro de devis déjà envoyé aurait pu être réattribué.
  
  Trouvé en analysant le scénario de restauration, puis couvert par un test dédié. Ce test a été vérifié en retirant la protection : il échoue alors.
- **Écran d'accueil** : le titre débordait de 40 points sur un écran de 360 points quand la synchronisation était en erreur.
- **Test PDF** : `pdftotext` était absent des machines de la CI. L'outil y est désormais installé et le contrôle du contenu du PDF s'exécute réellement.
- Antérieurs : conflit non résolu dans la parité du tableau de bord, menu déroulant trop étroit, responsable de projet perdu à la synchronisation, réglage RLS des tests en superutilisateur.

## 5. Ce qui n'est pas testé

- **Aucun test sur iPhone** : pas de Mac dans la chaîne de construction (décision D-09).
- **Aucun test de charge.** La phase 1 vise quelques utilisateurs.
- **Aucun test sur l'hébergement réel**, qui n'est pas choisi (D-06). La pile Docker est testée telle qu'elle sera déployée, mais pas le réseau, les sauvegardes ni le disque de l'hébergeur.
- **Le télémètre Bluetooth** n'est pas branché (D-02).
- **Accessibilité** : la taille minimale des boutons et le contraste de la charte sont respectés. Il n'y a pas eu d'essai avec un lecteur d'écran.
