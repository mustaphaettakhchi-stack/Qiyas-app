# Guide d'utilisation — LAMAALAM

Pour l'équipe de Group LAMAALAM (administrateurs et collaborateurs) et pour les clients invités dans leur espace.

## 1. Se connecter

1. Ouvrir l'application ; au premier lancement, saisir l'**adresse du serveur** (fournie par l'administrateur, commence par `https://`).
2. Adresse e-mail et mot de passe, puis le **code à 6 chiffres** de votre application d'authentification (Aegis, FreeOTP…). À la toute première connexion, l'application vous fait installer cette double authentification : scannez le QR code, saisissez un code, puis **notez les codes de secours** affichés (ils servent si vous perdez votre téléphone).
3. Après 5 mots de passe faux, le compte est bloqué un moment : attendez ou demandez à l'administrateur.

Téléphone perdu ou changé : l'administrateur réinitialise votre double authentification (Profil → *Équipe et invitations*).

## 2. Les onglets

| Onglet | Contenu |
| --- | --- |
| **Accueil** | Messages de clients en attente de réponse, indicateurs (chantiers actifs, devis à valider, à envoyer, en attente, acceptés), raccourcis *Nouveau projet* / *Nouveau devis*, liste « À faire », derniers projets, dernières opérations |
| **Projets** | Tous les projets, filtres par état |
| **Clients** | Fiches clients, consentement, projets du client |
| **Bibliothèque** | Ouvrages, matériaux, fournisseurs, prix (modifiable par l'administrateur seul) |
| **Profil** | Entreprise (ICE, IF, RC, patente, TVA par défaut, mentions), équipe, export de vos données, déconnexion |

La pastille en haut à droite indique l'état de la synchronisation : *Synchronisé*, *N à envoyer*, *Hors ligne*, *N conflits*… Toucher la pastille ouvre l'écran **Synchronisation**.

## 3. Travailler hors connexion

Tout se saisit sans réseau : les fiches sont gardées sur le téléphone et envoyées dès que la connexion revient (ou en tirant l'écran d'accueil vers le bas). Si une même fiche a été modifiée ailleurs entre-temps, elle apparaît en **conflit** sur l'écran Synchronisation : choisissez *Garder la mienne* ou *Garder celle du serveur*. Rien n'est écrasé sans votre choix.

## 4. Un chantier, du relevé au devis

1. **Client** : *Clients* → nouveau client. Cocher le **consentement** du client avant toute photo de son domicile.
2. **Projet** : *Accueil* → *Nouveau projet*, choisir le client, la nature des travaux, l'adresse du chantier. La référence `LMA-AAAA-NNNN` est attribuée par le serveur à la première synchronisation.
3. **Pièces** : sur la fiche projet, ajouter chaque pièce, en *Rectangle* ou *Mur par mur* (angles, angles rentrants), hauteur, ouvertures, éléments comptés (prises, points d'eau…). Chaque cote garde son origine ; une valeur standard reste « à vérifier ». Le plan dessine les vrais contours et signale une pièce qui ne se referme pas.
4. **Métré** : *Ouvrir le métré* → vérifier les quantités par lot et par pièce → *Valider le métré* (les cotes non vérifiées doivent être acceptées explicitement). Si une cote change ensuite, le métré passe « à revalider ».
5. **Devis** : *Passer au devis* → *Ajouter un ouvrage de la bibliothèque* ou *Ligne libre*. Les quantités viennent du métré (perte affichée sur la ligne). Prix de vente direct ou calculé (fournitures + main-d'œuvre, frais, marge), TVA par ligne, remise, acompte, MAD ou euros (taux, date et source obligatoires).
6. **Validation** (administrateur) : *Valider le devis*. Impossible si un prix manque ou si le métré n'est pas validé à jour. Le numéro `DV-AAAA-NNNN` est attribué par le serveur ; le devis est alors **figé** : pour le changer, *Modifier : créer une nouvelle version* (`-v2`…).
7. **Envoi** : *Envoyer au client* → *Envoyer le PDF (WhatsApp, e-mail…)*, puis marquer comme envoyé. Le PDF ne montre jamais les déboursés ni la marge et ne comporte pas de signature électronique : le client signe à la main.
8. **Réponse du client** : accepté ou refusé, avec une note. Le statut du projet suit automatiquement.

## 5. Espace client

Le client consulte ses projets sur son propre téléphone, en lecture seule.

- **Inviter un client** (administrateur) : fiche client → *Inviter dans l'espace client*. Le lien d'invitation (valable 72 heures) est envoyé par e-mail si la messagerie est configurée, sinon transmettez-le vous-même au client, à lui seul.
- **Ce que voit le client** : ses projets, les devis **envoyés** (montants, statut, PDF), les photos que vous avez **choisi de partager**, les grandes étapes, les messages. Jamais les autres clients, les déboursés, les marges ni les photos internes.
- **Partager** : fiche projet → *Espace client* → *Partager* une photo (le client reçoit une copie sans localisation GPS). Le partage se retire à tout moment avec l'interrupteur. Le PDF d'un devis envoyé est publié automatiquement après synchronisation (bouton *Publier* en secours).
- **Messages** : *Espace client* → *Messages avec le client*. Les messages non lus apparaissent en tête de l'Accueil.

**Pour le client** : connexion avec l'adresse e-mail et le mot de passe choisis à l'invitation ; la liste « Mes projets » s'ouvre. Toucher un projet pour voir ses devis (toucher un devis ouvre son PDF), ses photos, ses étapes ; le bouton *Messages* permet d'écrire à l'équipe. Pour accepter un devis : le retourner daté et signé à Group LAMAALAM. Une connexion internet est nécessaire.

## 6. Administrateur : équipe et bibliothèque

- **Équipe** : Profil → *Équipe et invitations* → *Inviter un membre* (collaborateur ou administrateur). Suspendre un compte, changer un profil, créer un lien de nouveau mot de passe (*Mot de passe oublié : crée un lien à transmettre*), réinitialiser une double authentification.
- **Bibliothèque** : ouvrages (unité, base de quantité, perte, TVA, prix), matériaux, fournisseurs ; *Historique des prix* ; *Importer un fichier CSV* (tout ou rien, erreurs indiquées par numéro de ligne). Un prix vide reste « à renseigner » et bloque la validation des devis qui l'utilisent. Les prix d'achat ne sont jamais transmis aux collaborateurs.

## 7. Si le serveur a été restauré

L'écran Synchronisation affiche « Le serveur a été restauré depuis une sauvegarde » et la synchronisation est suspendue. Touchez *Exporter mes données* par précaution, puis *Reprendre la synchronisation*. Vos fiches absentes du serveur lui sont renvoyées ; celles en conflit : choisissez *Garder la mienne*. Détails : [`RESTORE.md`](RESTORE.md), § 4.

## 8. Confidentialité

- Les photos restent sur le téléphone, sauf celles partagées dans l'espace client.
- Ne transmettez jamais un lien d'invitation ou de mot de passe à une autre personne que son destinataire.
- *Exporter mes données* produit un fichier lisible : conservez-le en lieu sûr et supprimez-le une fois inutile.
