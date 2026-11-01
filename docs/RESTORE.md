# Restauration — LAMAALAM

À lire **avant** d'en avoir besoin. Sauvegardes : [`BACKUP.md`](BACKUP.md).

## 1. Quand restaurer

| Situation | Que faire |
| --- | --- |
| Serveur perdu (panne, hébergeur, piratage) | Nouvelle machine : [`INSTALLATION.md`](INSTALLATION.md) § 2, puis § 2 ci-dessous. En cas de piratage, nouvelle machine **et** nouveaux secrets (§ 6) |
| Mise à jour ratée | [`DEPLOYMENT.md`](DEPLOYMENT.md) § 2 (retour arrière) |
| Données effacées ou corrompues par erreur | Restauration de la dernière archive saine sur le serveur en place |

Une restauration ramène le serveur **à la date de l'archive**. Ce qui a été saisi après n'existe plus sur le serveur, mais se trouve encore sur les téléphones (§ 4).

## 2. Procédure

Il faut : la machine (Docker, git, age installés), le dépôt cloné à la version du code de l'archive ou plus récente, l'archive (`.tar.age`) et son empreinte (`.tar.age.sha256`), la **clé privée** de sauvegarde.

```bash
cd /opt/lamaalam
deploy/restore.sh /chemin/lamaalam-AAAAMMJJ-HHMMSS.tar.age --identity /chemin/cle-privee.txt
```

Le script :

1. contrôle l'empreinte de l'archive, la déchiffre et contrôle chacun de ses éléments. Une mauvaise clé ou une archive abîmée l'arrête **avant toute modification** ;
2. installe le `.env` de l'archive s'il n'y en a pas (machine neuve). Si un `.env` existe avec une autre clé de double authentification, il s'arrête : relancer avec `--use-archive-env` (l'ancien `.env` est gardé en `.env.avant-restauration`) ;
3. demande de taper `RESTAURER` (ou `--yes` pour un usage scripté) ;
4. arrête les services, **remplace** la base et les fichiers par ceux de l'archive ;
5. redémarre ; les migrations mettent à niveau une archive plus ancienne que le code ;
6. prépare le serveur pour les téléphones (§ 4) et inscrit la restauration au journal d'audit.

**Durée mesurée** : 17 secondes sur la machine de développement, avec l'image Docker en cache. Sur une machine vierge, la construction de l'image s'y ajoute : voir le temps relevé par la CI dans [`TEST_REPORT.md`](TEST_REPORT.md). Le temps croît avec le volume des photos.

**Dépendance à Docker Hub** : sur une machine neuve, les images PostgreSQL, Caddy et Python sont téléchargées depuis Docker Hub, qui limite les téléchargements anonymes (refus « 429 Too Many Requests » constaté lors des essais après des téléchargements répétés). Parade, une fois par mois, sur le serveur : `docker save postgres:16 caddy:2 python:3.13-slim lamaalam-api:local | gzip > /var/backups/lamaalam/images-docker.tar.gz` (copié hors du serveur avec les archives) ; sur la machine neuve, `gunzip -c images-docker.tar.gz | docker load` avant `deploy/restore.sh`. Ces images ne contiennent aucune donnée de Group LAMAALAM.

Après une restauration sur une nouvelle machine, faire pointer le nom de domaine vers sa nouvelle adresse IP. Le certificat HTTPS est obtenu automatiquement.

## 3. Après la restauration

1. `curl https://<domaine>/api/v1/health` répond `{"status":"ok"}`.
2. Un administrateur se connecte avec son mot de passe **et son code habituel** : cela prouve que la clé de double authentification est la bonne.
3. Ouvrir un projet récent, un devis, une photo partagée.
4. Accueil → *Dernières opérations* : « Sauvegarde restaurée » apparaît.
5. Prévenir l'équipe : chaque téléphone affiche « serveur restauré » à la synchronisation suivante (§ 4).
6. Consigner dans le registre d'exploitation : date, archive utilisée, durée, anomalies.

## 4. Les téléphones après une restauration

Sans précaution, une restauration ferait perdre en silence le travail fait entre la sauvegarde et l'incident. Ce travail n'existe plus sur le serveur, mais les téléphones le croient envoyé. Trois protections sont donc en place :

- **Rien ne se mélange.** Chaque restauration change l'« époque » du serveur. Avant tout envoi, le téléphone la compare à la sienne. Si elle a changé, il suspend sa synchronisation et explique la situation sur l'écran *Synchronisation*.
- **Reprise décidée par l'utilisateur.** Il exporte ses données par précaution, puis touche *Reprendre la synchronisation*. Le téléphone retélécharge tout et applique trois règles :
  - les fiches inconnues du serveur (créées après la sauvegarde) lui sont renvoyées comme nouvelles ;
  - quand le serveur a une version **plus ancienne** que celle du téléphone, la fiche passe en conflit au lieu d'être écrasée : choisir *Garder la mienne* ;
  - rien n'est jamais supprimé du téléphone.
- **Pas de numéro en double.** Les 100 références suivantes de chaque compteur (projets, devis) sont réservées. Un numéro de devis déjà envoyé à un client n'est donc jamais réattribué à un autre devis. La numérotation présente un trou, inscrit au journal d'audit. Ce choix est à faire valider par l'expert-comptable, avec les mentions légales.

Limites :
- Un devis **envoyé, accepté ou refusé** après la sauvegarde est renvoyé comme nouveau et **refusé par le serveur** (un devis ne naît pas « envoyé ») : l'écran du devis affiche « Envoi refusé ». L'administrateur le recrée à partir du PDF envoyé au client et prévient le client si le numéro change.
- Un devis seulement **validé** (pas encore envoyé), renvoyé par un administrateur, est revalidé avec un **nouveau** numéro : aucun doublon possible, puisqu'il n'est jamais parti.
- Une fiche renvoyée reçoit une nouvelle référence de projet.
- Les photos partagées après la sauvegarde sont à repartager.
- Les messages de l'espace client postés après la sauvegarde sont perdus.

## 5. Exercice mensuel (obligatoire)

Sur une **machine d'essai**, jamais sur le serveur de production :

```bash
tool/restore_drill.sh
```

L'exercice comporte les étapes suivantes :
1. installer un serveur neuf et y créer un administrateur avec double authentification, un client, un projet, une photo partagée et un message ;
2. sauvegarder ;
3. détruire tout (conteneurs, volumes, image, `.env`) ;
4. restaurer en chronométrant ;
5. vérifier la connexion avec le même secret de double authentification, le projet, le fichier (identique octet pour octet), le message et l'inscription au journal ;
6. vérifier qu'une mauvaise clé est refusée sans rien arrêter.

Il tourne aussi à chaque modification du code (CI, job « exploitation »).

Une fois par trimestre, restaurer **la vraie dernière archive de production** sur la machine d'essai, avec la vraie clé privée, puis vérifier les points du § 3. C'est le seul moyen de savoir que les archives réelles et la clé conservée fonctionnent.

## 6. Après un piratage

Restaurer sur une **nouvelle** machine, puis changer tous les secrets :
- `LAMAALAM_JWT_SECRET` : cela déconnecte tout le monde ;
- les mots de passe de la base (rôles `lamaalam_owner` et `lamaalam_app`, à modifier aussi dans PostgreSQL) ;
- le mot de passe d'application SMTP.

La clé de double authentification ne peut pas être changée sans que chaque compte refasse sa double authentification. Faire ce choix si le serveur piraté détenait `.env`, c'est-à-dire toujours. Revoir aussi le journal d'audit et prévenir les personnes concernées (loi 09-08 ; voir [`SECURITY.md`](../SECURITY.md)).
