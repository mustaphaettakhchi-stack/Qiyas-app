# Installation — LAMAALAM

Installation d'un serveur neuf, puis des téléphones. Pour les mises à jour : [`DEPLOYMENT.md`](DEPLOYMENT.md).

> **Rien n'est acheté ni souscrit par ces procédures.** Le serveur, le nom de domaine et, pour iOS, le compte développeur Apple ont un coût : ils relèvent de la décision D-06 (hébergement non validé à ce jour) et de l'accord écrit de Group LAMAALAM.

## 1. Ce qu'il faut

| Élément | Minimum conseillé | Remarque |
| --- | --- | --- |
| Serveur | Linux 64 bits (Debian 12 ou Ubuntu 24.04), 2 Go de mémoire, 2 processeurs, 40 Go de disque | Un VPS suffit pour la phase 1 (quelques utilisateurs) |
| Nom de domaine | Un sous-domaine, par exemple `api.grouplamaalam.ma`, pointant (enregistrement A) vers l'adresse IP du serveur | Nécessaire au certificat HTTPS gratuit (Let's Encrypt) |
| Ports ouverts | 22 (SSH, limité), 80 et 443 | 80 sert uniquement à l'obtention du certificat et à la redirection |
| Logiciels | Docker Engine avec Docker Compose v2, git, age | Tous Open Source, voir le registre des licences |
| Poste du gérant | Un ordinateur avec `age` | Pour créer et garder la clé privée des sauvegardes, hors du serveur |

## 2. Préparer le serveur (Debian ou Ubuntu)

```bash
# Mises à jour de sécurité automatiques
sudo apt-get update && sudo apt-get install -y unattended-upgrades git age ufw
# Docker (dépôt officiel Docker, édition Community, gratuite) : https://docs.docker.com/engine/install/
# Pare-feu : SSH, HTTP, HTTPS seulement
sudo ufw allow OpenSSH && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable
```

Accès SSH par clé uniquement (`PasswordAuthentication no` dans `/etc/ssh/sshd_config`), pas de connexion directe en `root`.

## 3. Installer le serveur LAMAALAM

```bash
sudo mkdir -p /opt/lamaalam && sudo chown "$USER" /opt/lamaalam
git clone https://github.com/mustaphaettakhchi-stack/Qiyas-app.git /opt/lamaalam
cd /opt/lamaalam
git checkout <version validée>          # une étiquette ou un commit précis, jamais « au hasard »

cp .env.example .env && chmod 600 .env
```

Remplir `.env` :

| Variable | Valeur |
| --- | --- |
| `LAMAALAM_DOMAIN` | le sous-domaine, sans `https://` |
| `LAMAALAM_PUBLIC_BASE_URL` | `https://` + le sous-domaine |
| `LAMAALAM_OWNER_DB_PASSWORD`, `LAMAALAM_APP_DB_PASSWORD`, `LAMAALAM_JWT_SECRET` | `python3 -c "import secrets;print(secrets.token_urlsafe(48))"` (une valeur différente pour chacun) |
| `LAMAALAM_TOTP_ENCRYPTION_KEY` | `python3 -c "import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).decode())"` |
| `LAMAALAM_SMTP_*` | facultatif : envoi des invitations par e-mail (décision D-08 ; mot de passe d'application Gmail, jamais le mot de passe du compte) |

> **La clé `LAMAALAM_TOTP_ENCRYPTION_KEY` chiffre les secrets de double authentification.** Perdue, plus personne ne peut se connecter avec son code : chaque compte devra refaire sa double authentification. Elle est incluse dans chaque sauvegarde chiffrée ; ne la changez jamais sur un serveur en service.

Démarrer :

```bash
deploy/deploy.sh --no-backup     # première installation : rien à sauvegarder
```

Le script vérifie `.env`, construit l'image, crée la base, applique les migrations, démarre l'API derrière Caddy (HTTPS automatique) et attend qu'elle réponde. Vérification : `curl https://api.grouplamaalam.ma/api/v1/health` doit répondre `{"status":"ok"}`.

## 4. Premier administrateur

Aucun compte n'existe par défaut.

```bash
docker compose run --rm --no-deps migrate python -m app.cli create-admin \
  --organization "Group LAMAALAM" --email adresse@exemple.ma --name "Prénom Nom"
```

Le mot de passe est demandé de façon masquée (12 caractères au moins, refusé s'il est trop facile). La double authentification est mise en place à la première connexion depuis l'application, avec une application TOTP libre (Aegis, FreeOTP). **Conservez les codes de secours** affichés à ce moment.

## 5. Sauvegardes

À mettre en place **le jour même** : [`BACKUP.md`](BACKUP.md). Un serveur sans sauvegarde testée n'est pas en service.

## 6. Téléphones

**Android** : installer l'APK `lamaalam-serveur.apk` (artefact de la CI, onglet *Actions* du dépôt), en autorisant l'installation depuis cette source. Au premier lancement, renseigner l'adresse du serveur (`https://api.grouplamaalam.ma`) sur l'écran de connexion. Aucune publication sur le Play Store n'est faite sans accord.

**iOS** : la compilation exige un Mac avec Xcode, et l'installation sur des iPhone hors développement un compte développeur Apple (payant, décision D-09, non engagé).

Les membres de l'équipe et les clients ne créent pas de compte eux-mêmes : l'administrateur les invite (Profil → *Équipe et invitations* ; fiche client → *Inviter dans l'espace client*). Voir [`USER_GUIDE.md`](USER_GUIDE.md).
