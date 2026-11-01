# Déploiement et exploitation — LAMAALAM

Mise à jour du serveur, retour arrière, surveillance. Première installation : [`INSTALLATION.md`](INSTALLATION.md).

## 1. Mettre à jour

```bash
cd /opt/lamaalam
git fetch --tags
git log --oneline HEAD..<nouvelle version>   # relire ce qui change
git checkout <nouvelle version>
deploy/deploy.sh
```

`deploy/deploy.sh` :

1. vérifie `.env` (droits `600`, secrets présents, `LAMAALAM_ENVIRONMENT=production`) ;
2. construit l'image de l'API ;
3. **sauvegarde le serveur en place** (`deploy/backup.sh`) : c'est le vrai retour arrière ;
4. redémarre les services ; le service `migrate` applique les migrations de la base avant que l'API ne démarre ;
5. attend que l'API réponde et affiche la version du schéma de la base.

Coupure de service : quelques secondes pendant le redémarrage de l'API. Les téléphones continuent de travailler hors connexion et se synchronisent ensuite.

Mettre à jour un jour ouvré, en matinée, jamais juste avant un départ en congé.

## 2. Revenir en arrière

Les migrations de la base ne s'annulent pas toujours sans perte. Le retour arrière fiable est la sauvegarde prise par `deploy.sh` juste avant la mise à jour :

```bash
git checkout <version précédente>
deploy/restore.sh /var/backups/lamaalam/lamaalam-AAAAMMJJ-HHMMSS.tar.age --identity /chemin/cle-privee.txt
```

Tout ce qui a été saisi entre la sauvegarde et le retour arrière est perdu côté serveur ; les téléphones le détectent et le renvoient (voir [`RESTORE.md`](RESTORE.md), § 4).

## 3. Commandes utiles

```bash
docker compose ps                         # état des services
docker compose logs --tail 200 api        # journal de l'API (jamais de mot de passe ni de jeton)
docker compose logs --tail 200 caddy      # HTTPS, certificats
docker compose exec db psql -U lamaalam_owner -d lamaalam   # console SQL (prudence)
```

Sauf indication contraire, lancer ces commandes depuis `/opt/lamaalam` (le fichier `.env` y est lu).

## 4. Surveillance sans service payant

- **Santé** : `https://<domaine>/api/v1/health`. Une tâche planifiée peut alerter par e-mail (via le relais SMTP déjà configuré) si la réponse n'est pas `ok`.
- **Sauvegardes** : vérifier chaque lundi la présence de l'archive de la nuit et sa copie hors du serveur (journal de `cron`).
- **Disque** : `df -h` ; au-delà de 80 % d'occupation, agrandir le disque ou réduire la conservation des sauvegardes.
- **Certificat** : renouvelé automatiquement par Caddy ; une erreur apparaît dans `docker compose logs caddy`.

## 5. Sécurité de l'exploitation

- `.env` : droits `600`, jamais dans Git, jamais envoyé par messagerie.
- Images Docker : mettre à jour avec le code (`deploy/deploy.sh` reconstruit l'image de l'API ; `docker compose pull db caddy` pour PostgreSQL et Caddy, avant un `deploy.sh`).
- **Non fait à ce stade** : chiffrement du disque du serveur (LUKS ou équivalent de l'hébergeur), analyse antivirus des fichiers reçus, épinglage des images par empreinte. À traiter avec le choix de l'hébergement (D-06).

## 6. Hébergement

Aucun hébergeur n'est validé (décision D-06 : Hostinger envisagé). Ces procédures fonctionnent sur tout serveur Linux avec Docker ; elles n'engagent aucun abonnement. Avant toute souscription : accord écrit de Group LAMAALAM sur le prix, la durée, la localisation des données (loi 09-08) et les sauvegardes de l'hébergeur.
