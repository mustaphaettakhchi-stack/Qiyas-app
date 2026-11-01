# Parcours utilisateurs et critères d'acceptation — LAMAALAM

Version 0.1 — 1er novembre 2026 — statut : **PROPOSITION, à valider**

Les parcours sont décrits pour la Phase 1 en détail et pour les phases suivantes à grandes lignes. Chaque critère d'acceptation est vérifiable (test automatisé ou recette manuelle documentée).

## Personas

| Persona | Profil | Contraintes |
| --- | --- | --- |
| **Administrateur** (direction LAMAALAM) | Valide prix, devis et utilisateurs | Bureau et chantier |
| **Responsable chantier** (collaborateur) | Visite, relève, suit les travaux ; pas forcément à l'aise avec l'informatique ni le métré | Une main, soleil, poussière, réseau faible, batterie limitée |
| **Client** | Particulier ou entreprise, consulte depuis son téléphone | Aucune formation ; doit comprendre seul |

## Règles d'ergonomie transverses (critères d'acceptation globaux)

- G1 — Une action principale par écran, bouton orange en bas, cible ≥ 48 dp.
- G2 — Toute saisie est enregistrée sans bouton « Enregistrer » ; indicateur « Enregistré sur le téléphone » / « Synchronisé ».
- G3 — Toute suppression demande confirmation et reste annulable 10 secondes (suppression logique).
- G4 — Aucun message d'erreur technique : chaque erreur dit ce qui s'est passé et quoi faire (ex. « Pas de réseau. Vos données sont gardées sur le téléphone et seront envoyées automatiquement. »).
- G5 — Retour arrière possible depuis chaque écran sans perte de saisie.
- G6 — Toutes les fonctions de Phase 1 sauf connexion initiale, synchronisation et espace client fonctionnent en mode avion.
- G7 — Unité affichée à côté de chaque valeur (m, m², m³, kg, l, u, forfait, MAD, EUR).
- G8 — Toute valeur par défaut ou estimée est visuellement distincte (pastille orange « à vérifier »).
- G9 — Aucun bouton visible sans action réelle ; une fonction d'une phase ultérieure n'apparaît pas dans l'interface.

---

## P1 — Première connexion d'un collaborateur

1. L'administrateur crée l'invitation (nom, e-mail, rôle).
2. Le collaborateur ouvre le lien, choisit son mot de passe, configure la 2FA (QR code lisible par une application TOTP libre), note ses codes de secours.
3. Il arrive sur le tableau de bord vide, avec un tutoriel de 3 écrans maximum (passable).

Critères :
- A1.1 — Un lien d'invitation expiré ou déjà utilisé affiche un message clair et ne crée aucun compte.
- A1.2 — Sans 2FA configurée, un collaborateur n'accède à aucune donnée.
- A1.3 — Cinq échecs de connexion déclenchent un délai croissant, journalisé dans `audit_logs`.

## P2 — Créer un dossier client et un projet (Menu 2)

1. Bouton « Nouveau projet » (tableau de bord).
2. Client : recherche d'un client existant ou création (nom, téléphone, e-mail facultatif, adresse, ville, consentement).
3. Projet : nature des travaux, nature du bien, nom, adresse du chantier (pré-remplie depuis le client), budget estimatif facultatif, date de visite, description, notes, photos initiales.
4. Le projet reçoit sa référence définitive à la synchronisation (référence provisoire marquée « provisoire » hors ligne).

Critères :
- A2.1 — Création possible en mode avion ; synchronisation automatique au retour du réseau, sans doublon.
- A2.2 — Deux projets ne peuvent jamais partager la même référence dans une organisation (contrainte base).
- A2.3 — Le numéro de téléphone marocain est normalisé (`+212…`) ; un numéro étranger est accepté avec indicatif.
- A2.4 — Le consentement est obligatoire pour enregistrer des photos du domicile du client.

## P3 — Relever une pièce manuellement (Menu 3, mode C, parcours principal en Phase 1)

1. Dans le projet : choisir l'étage (créé par défaut « RDC »), « Ajouter une pièce », type et nom.
2. Forme : rectangle (2 cotes) ou forme libre (mur après mur : longueur, angle, 90° par défaut).
3. Hauteur sous plafond.
4. Ouvertures : par mur, type, largeur, hauteur, allège ; dimensions standard proposées **en orange « à vérifier »**.
5. Chaque cote indique sa source (mètre, télémètre, valeur par défaut) ; la saisie au télémètre marque la cote « vérifiée ».
6. Aperçu du plan de la pièce à l'échelle, mis à jour en direct.
7. Photos de la pièce.

Critères :
- A3.1 — Une pièce rectangulaire 5,20 × 4,10 × 2,80 m avec 1 porte 0,83 × 2,04 et 2 fenêtres 1,20 × 1,25 donne : sol 21,32 m², périmètre 18,60 m, murs bruts 52,08 m², murs nets 47,3868 m² (affiché 47,39 m²), plinthes 17,77 m, volume 59,696 m³ (affiché 59,70 m³). *(Cas repris de Qiyas, à recalculer par le test.)*
- A3.2 — Une pièce en L saisie mur par mur donne la même surface qu'un calcul indépendant par décomposition en rectangles.
- A3.3 — Un polygone qui ne se referme pas (écart > seuil paramétré) affiche « Les cotes ne se referment pas : vérifiez la longueur des murs » et bloque la validation du métré de la pièce.
- A3.4 — Une cote hors plage (mur < 0,30 m ou > 30 m, hauteur < 1,80 m ou > 6 m — plages paramétrables) déclenche un avertissement, pas un blocage.
- A3.5 — Corriger une cote crée une nouvelle valeur ; l'ancienne reste consultable dans l'historique.

## P4 — Produire et valider le métré (Menu 4)

1. Onglet « Métré » du projet : tableau par pièce et par lot (sols, murs, plafonds, menuiseries, électricité, plomberie, maçonnerie).
2. Les quantités géométriques sont calculées ; les comptages (prises, points d'eau, démolitions…) sont saisis.
3. Chaque ligne peut être ouverte pour voir sa trace (pièce, cotes, formule, taux de perte).
4. « Valider le métré » : liste des cotes non vérifiées ; l'utilisateur vérifie ou accepte explicitement.

Critères :
- A4.1 — Le taux de perte est 0 % par défaut ; un taux non nul s'affiche sur la ligne (« + 10 % de perte »).
- A4.2 — Le métré validé est figé ; toute modification ultérieure d'une cote crée un nouveau métré à valider et signale le devis lié comme « basé sur un métré périmé ».
- A4.3 — Les résultats Dart (téléphone) et Python (serveur) sont identiques sur la suite de cas de test partagée.

## P5 — Gérer la bibliothèque de prix (Menu 11, administrateur)

1. Ajouter un ouvrage : code, nom, lot, unité, base de quantité, taux de perte, composants (matériaux et quantité par unité), main-d'œuvre, prix de vente.
2. Ajouter un matériau : fournisseur, unité, conditionnement, prix d'achat, prix de vente, ville, date.
3. Toute modification de prix crée une entrée d'historique avec sa source.

Critères :
- A5.1 — En production, la bibliothèque est vide au premier lancement.
- A5.2 — Un collaborateur ne voit pas les prix d'achat si le paramètre « masquer les prix d'achat » est actif.
- A5.3 — L'import CSV rejette toute ligne sans unité ou avec une unité inconnue, avec le numéro de ligne en cause.

## P6 — Créer, valider et envoyer un devis (Menu 7)

1. Depuis un métré validé : « Créer un devis » ; choix d'un modèle ou ajout d'ouvrages.
2. Les quantités viennent du métré ; un prix manquant bloque la ligne (« Prix à renseigner ») — **aucun prix n'est proposé par l'application**.
3. Réglages : devise, TVA par ligne, frais indirects, marge, remise, acompte, validité.
4. Aperçu PDF.
5. L'administrateur valide → version figée, numéro définitif attribué par le serveur.
6. Envoi : partage du PDF (WhatsApp, e-mail) et/ou publication dans l'espace client → statut « envoyé ».
7. Réponse du client consignée par l'équipe (« accepté » / « refusé », date, commentaire).

Critères :
- A6.1 — Le devis de référence (projet de 5 pièces Qiyas : 27 989 MAD HT, 5 598 MAD de TVA, 33 587 MAD TTC à 20 %) est reproduit au centime près par la nouvelle implémentation. *Précision (lot 1.6) : les montants exacts sont 27 988,95 MAD HT, 5 597,79 MAD de TVA et 33 586,74 MAD TTC ; « 27 989 » était un arrondi d'affichage. Le devis affiche désormais les montants au centime.*
- A6.2 — Une version validée ne peut plus être modifiée (refus côté serveur testé) ; « Modifier » crée la version n+1.
- A6.3 — Un devis en EUR affiche le taux de change saisi et sa date sur le PDF.
- A6.4 — Le PDF affiche correctement un nom de client en arabe.
- A6.5 — Le PDF ne contient aucun déboursé ni marge.
- A6.6 — Aucune mention « signé électroniquement » ou équivalent n'apparaît.

## P7 — Tableau de bord (Menu 1)

Critères :
- A7.1 — Chaque indicateur (chantiers actifs, prospects, devis en attente, devis acceptés) est égal au résultat d'une requête de contrôle sur un jeu de test.
- A7.2 — Les raccourcis « Nouveau projet », « Nouveau devis » fonctionnent ; « Nouveau scan » n'apparaît qu'en Phase 2 (règle G9).

## P8 — Espace client (Menu 10, Phase 1 en lecture seule)

1. Le client reçoit une invitation par e-mail, crée son mot de passe.
2. Il voit la liste de **ses** projets, l'avancement, les devis envoyés (PDF), les photos et étapes marquées visibles, et peut écrire au responsable.

Critères :
- A8.1 — Pour chaque route de l'API, un test automatisé prouve qu'un client ne peut lire aucune ressource d'un autre client (réponse 404).
- A8.2 — Un élément non marqué « visible par le client » n'apparaît jamais, même via l'API directe.
- A8.3 — Les liens de fichiers expirent en 15 minutes au plus.
- A8.4 — Les photos partagées sont dépourvues de coordonnées GPS.

## P9 — Travailler sans réseau puis synchroniser

Critères :
- A9.1 — Créer projet, pièces, cotes, photos et brouillon de devis en mode avion, redémarrer le téléphone, réactiver le réseau : tout est synchronisé, sans doublon ni perte.
- A9.2 — Deux collaborateurs modifiant la même cote hors ligne : le second à synchroniser voit un écran de conflit montrant les deux valeurs, leurs auteurs et dates ; rien n'est écrasé en silence.
- A9.3 — Une coupure pendant l'envoi d'une vidéo de 500 Mo reprend là où elle s'est arrêtée.

---

## Parcours des phases suivantes (aperçu)

- **P10 — Scan photo guidé (Phase 2)** : choix de la cible → consignes (lumière, déplacement) → prise de vue avec retour immédiat (net / flou, couverture) → cote de référence + cote de contrôle → envoi différé → rapport de fiabilité → cotes « estimées » proposées → correction et validation. Critère clé : un scan dont le rapport est insuffisant ne peut alimenter aucun métré sans validation manuelle cote par cote.
- **P11 — Scan vidéo (Phase 2)** : filmer lentement → contrôle de durée et de stabilité → envoi → extraction d'images clés → même suite que P10.
- **P12 — Plan et 3D (Phase 3)** : plan 2D depuis le relevé, déplacement de cloisons, mobilier, export PDF/PNG/OBJ/PLY/GLB.
- **P13 — Avant / après (Phase 3)** : choix d'une pièce et d'un style → matériaux → aperçu rapide → rendu détaillé → rendu photoréaliste → partage au client avec mention « Simulation non contractuelle ».
- **P14 — Suivi de chantier (Phases 1–3)** : journal hebdomadaire, photos avant / pendant / après, incidents, matériaux utilisés, dépenses, visibilité client élément par élément.
- **P15 — Montage vidéo (Phase 4)** : sélection des médias → gabarit et format → prévisualisation → validation → export.
