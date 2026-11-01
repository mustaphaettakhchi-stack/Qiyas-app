# Sauvegardes — LAMAALAM

Une sauvegarde non testée n'est pas une sauvegarde : chaque mois, une restauration complète est faite sur une machine d'essai ([`RESTORE.md`](RESTORE.md), § 5).

## 1. Ce que contient une archive

| Élément | Origine |
| --- | --- |
| Base de données complète | `pg_dump` (format personnalisé) |
| Fichiers : photos partagées, PDF de devis | volume `lamaalam_files-data` |
| Fichier `.env` | secrets du serveur, **dont la clé de la double authentification** : sans elle, aucun compte ne pourrait plus se connecter avec son code |
| Manifeste | date, version du schéma, version du code, nombre d'organisations, de comptes, de projets, de fichiers |
| `SHA256SUMS` | empreinte de chaque élément, contrôlée à la restauration |

L'ensemble est chiffré avec **age** vers une **clé publique**. Le serveur n'a que cette clé publique : il peut créer des archives mais ne peut pas les lire. Même un serveur piraté ne livre donc pas ses sauvegardes.

La base est exportée avant les fichiers. Aucun fichier n'étant jamais effacé physiquement, chaque fiche de la base retrouve son fichier (un envoi pendant la sauvegarde ne donne, au pire, qu'un fichier en trop).

## 2. Créer la clé (une fois, sur le poste du gérant, pas sur le serveur)

```bash
age-keygen -o lamaalam-sauvegardes-cle-privee.txt
# affiche « Public key: age1… » : c'est la clé publique
```

La **clé privée** (`AGE-SECRET-KEY-…`) est la seule façon de relire les sauvegardes :

- deux copies au moins : une clé USB dans un coffre, une copie imprimée ou un gestionnaire de mots de passe ;
- jamais sur le serveur, jamais dans Git, jamais envoyée par e-mail ou WhatsApp ;
- sa perte rend toutes les archives illisibles. Sa divulgation les rend lisibles : en créer alors une nouvelle et refaire une sauvegarde.

Sur le serveur, la clé publique seule :

```bash
sudo mkdir -p /etc/lamaalam
echo "age1…" | sudo tee /etc/lamaalam/sauvegarde-cle-publique.txt
```

Plusieurs lignes `age1…` = plusieurs personnes capables de restaurer (par exemple le gérant et le comptable).

## 3. Réglages (dans `.env`)

```ini
LAMAALAM_BACKUP_RECIPIENTS=/etc/lamaalam/sauvegarde-cle-publique.txt
LAMAALAM_BACKUP_DIR=/var/backups/lamaalam
LAMAALAM_BACKUP_KEEP_DAYS=30
# Facultatif : copie hors du serveur, appelée avec l'archive et son empreinte
# LAMAALAM_BACKUP_COPY_CMD=/opt/lamaalam/deploy/copie-hors-site.sh
```

`deploy/backup.sh` refuse de fonctionner si le fichier de clés contient une clé **privée**.

## 4. Sauvegarde quotidienne

```bash
sudo crontab -e
# Tous les jours à 2 h 17 (heure du serveur)
17 2 * * * cd /opt/lamaalam && deploy/backup.sh >> /var/log/lamaalam-backup.log 2>&1
```

Une archive `lamaalam-AAAAMMJJ-HHMMSS.tar.age` et son empreinte `.sha256` sont créées. Les archives de plus de `LAMAALAM_BACKUP_KEEP_DAYS` jours sont supprimées ; les 7 plus récentes sont toujours gardées. Deux sauvegardes ne peuvent pas tourner en même temps (verrou).

Sauvegarde à la demande : `deploy/backup.sh`. `deploy/deploy.sh` en fait une avant chaque mise à jour.

## 5. Copie hors du serveur (obligatoire)

Une sauvegarde restée sur le serveur disparaît avec lui. Il faut une copie **sur un support physiquement distinct** :

- **sans coût** : un ordinateur ou un NAS de Group LAMAALAM qui récupère chaque nuit les archives (`rsync -a serveur:/var/backups/lamaalam/ /sauvegardes/lamaalam/`), ou la commande `LAMAALAM_BACKUP_COPY_CMD` qui les pousse vers lui ;
- **un stockage en ligne** (offre de l'hébergeur ou autre) est un service payant : accord écrit préalable. Les archives étant chiffrées, le prestataire ne peut pas les lire.

Conservation recommandée hors du serveur : 7 quotidiennes, 4 hebdomadaires, 12 mensuelles.

## 6. Écarts avec SECURITY.md (version initiale)

- **age** remplace **restic**, prévu au départ. Avec restic, le mot de passe de chiffrement devrait se trouver sur le serveur pour l'automatisation. Avec age, le serveur n'a que la clé publique. Contrepartie : pas de déduplication. Chaque archive est complète, ce qui reste raisonnable tant que les photos partagées sont peu nombreuses (à réévaluer avec les vidéos de chantier).
- La conservation sur le serveur est de 30 jours. La rotation hebdomadaire et mensuelle se fait sur la copie hors du serveur.

## 7. Ce qui n'est PAS sauvegardé

- Les photos restées sur les téléphones (non partagées dans l'espace client) : seul le téléphone les détient. L'export de l'application (Profil → *Exporter mes données*) ne contient que les fiches, pas les photos.
- Le certificat HTTPS : Caddy en obtient un nouveau automatiquement.
