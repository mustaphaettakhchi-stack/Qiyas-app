#!/usr/bin/env bash
# Restauration complète d'une sauvegarde LAMAALAM (RESTORE.md).
#
#   deploy/restore.sh ARCHIVE.tar.age --identity CLE_PRIVEE.txt [--yes] [--use-archive-env]
#
# Fonctionne sur une machine vierge (Docker installé, dépôt cloné) comme sur le serveur en
# place. ATTENTION : la base et les fichiers actuels sont REMPLACÉS par ceux de l'archive.
#
# Fichier .env :
#   - absent : celui de l'archive est installé (cas de la machine vierge) ;
#   - présent : il est conservé s'il porte la même clé de double authentification que
#     l'archive ; sinon arrêt, sauf --use-archive-env (l'ancien est gardé en .env.avant-restauration).
. "$(dirname "$0")/lib.sh"

ARCHIVE=""; IDENTITY=""; YES=0; USE_ARCHIVE_ENV=0
while [ $# -gt 0 ]; do
  case "$1" in
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --yes) YES=1; shift ;;
    --use-archive-env) USE_ARCHIVE_ENV=1; shift ;;
    -*) die "option inconnue : $1" ;;
    *) ARCHIVE="$1"; shift ;;
  esac
done
[ -f "$ARCHIVE" ] || die "archive introuvable : ${ARCHIVE:-(aucune)}"
[ -f "$IDENTITY" ] || die "clé privée age introuvable (--identity), voir BACKUP.md"
need docker age sha256sum tar
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 requis (docker compose)"

START=$(date +%s)
umask 077
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. Contrôles avant toute modification.
if [ -f "$ARCHIVE.sha256" ]; then
  (cd "$(dirname "$ARCHIVE")" && sha256sum -c --quiet "$(basename "$ARCHIVE").sha256") || die "empreinte de l'archive incorrecte : fichier altéré ou incomplet"
else
  log "Pas de fichier .sha256 à côté de l'archive : l'intégrité est vérifiée après déchiffrement seulement"
fi
log "Déchiffrement"
age -d -i "$IDENTITY" "$ARCHIVE" | tar -C "$WORK" -xf - || die "déchiffrement impossible (mauvaise clé privée ou archive abîmée)"
(cd "$WORK" && sha256sum -c --quiet SHA256SUMS) || die "contenu de l'archive incohérent (empreintes SHA-256)"
log "Archive : $(tr '\n' ' ' < "$WORK/manifest.txt")"

archived_key="$(grep -E '^LAMAALAM_TOTP_ENCRYPTION_KEY=' "$WORK/env.secret" | cut -d= -f2-)"
if [ ! -f "$ENV_FILE" ]; then
  log "Pas de $ENV_FILE : installation de celui de l'archive"
  install -m 600 "$WORK/env.secret" "$ENV_FILE"
elif [ "$(env_value LAMAALAM_TOTP_ENCRYPTION_KEY)" != "$archived_key" ]; then
  if [ "$USE_ARCHIVE_ENV" = 1 ]; then
    cp -p "$ENV_FILE" "$ENV_FILE.avant-restauration"
    install -m 600 "$WORK/env.secret" "$ENV_FILE"
    log "$ENV_FILE remplacé par celui de l'archive (ancien : $ENV_FILE.avant-restauration)"
  else
    die "la clé de double authentification de $ENV_FILE diffère de celle de l'archive : les codes de tous les comptes seraient refusés. Relancez avec --use-archive-env (recommandé) ou corrigez $ENV_FILE."
  fi
fi
check_env

if [ "$YES" != 1 ]; then
  printf 'La base et les fichiers actuels vont être REMPLACÉS. Tapez RESTAURER pour continuer : ' >&2
  read -r answer
  [ "$answer" = "RESTAURER" ] || die "restauration abandonnée"
fi

# 2. Image, arrêt de la pile, volumes de données neufs.
docker image inspect "$IMAGE" >/dev/null 2>&1 || build_image
log "Arrêt des services"
compose down --remove-orphans >&2
docker volume rm -f "${PROJECT}_db-data" "${PROJECT}_files-data" >/dev/null

# 3. Base : une base vide est créée par le conteneur (avec le rôle applicatif), puis remplie.
log "Restauration de la base"
compose up -d db >&2
wait_db
compose exec -T db pg_restore -U lamaalam_owner -d lamaalam --exit-on-error --no-password < "$WORK/db.dump" \
  || die "pg_restore en échec"

# 4. Fichiers, avec leur propriétaire d'origine (utilisateur de l'API).
log "Restauration des fichiers"
docker run --rm -i --network none -v "${PROJECT}_files-data:$FILES_PATH" --entrypoint tar "$IMAGE" \
  -C "$FILES_PATH" -xf - < "$WORK/files.tar"

# 5. Démarrage : les migrations mettent à niveau une sauvegarde plus ancienne que le code.
log "Démarrage"
compose up -d --no-build >&2
wait_healthy
backup_date="$(grep '^created_at=' "$WORK/manifest.txt" | cut -d= -f2)"
# Séquence de synchronisation, compteurs de références et époque : voir app/cli.py, record_restore.
compose run --rm --no-deps -T migrate python -m app.cli record-restore \
  --archive "$(basename "$ARCHIVE")" --backup-date "$backup_date" >&2

COUNTS="$(compose exec -T db psql -U lamaalam_owner -d lamaalam -tA -F ' ' -c \
  "SELECT (SELECT count(*) FROM organizations), (SELECT count(*) FROM users), (SELECT count(*) FROM projects), (SELECT count(*) FROM files)")"
log "Restauration terminée en $(( $(date +%s) - START )) s — organisations, comptes, projets, fichiers : $COUNTS"
log "Contrôles à faire maintenant : RESTORE.md, section « Après la restauration »"
