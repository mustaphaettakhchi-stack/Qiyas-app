#!/usr/bin/env bash
# Sauvegarde complète et chiffrée du serveur LAMAALAM (BACKUP.md).
#
# Contenu : base PostgreSQL (pg_dump), fichiers (photos, PDF), fichier .env (secrets, dont la
# clé de chiffrement de la double authentification), manifeste avec empreintes SHA-256.
# Chiffrement : age, vers une ou plusieurs clés PUBLIQUES (LAMAALAM_BACKUP_RECIPIENTS).
# Le serveur ne détient jamais la clé de déchiffrement : elle reste hors ligne chez
# Group LAMAALAM. Une archive n'est donc lisible qu'avec cette clé, même si le serveur
# est compromis.
#
# Variables (dans l'environnement ou dans .env) :
#   LAMAALAM_BACKUP_DIR         dossier des archives (défaut /var/backups/lamaalam)
#   LAMAALAM_BACKUP_RECIPIENTS  fichier des clés publiques age (obligatoire)
#   LAMAALAM_BACKUP_KEEP_DAYS   durée de conservation (défaut 30 jours ; 7 archives au moins gardées)
#   LAMAALAM_BACKUP_COPY_CMD    commande facultative de copie hors du serveur, appelée avec le
#                               chemin de l'archive (ex. rsync vers une autre machine)
. "$(dirname "$0")/lib.sh"

need docker age sha256sum tar flock
check_env

from_env() { local v="${!1:-}"; [ -n "$v" ] || v="$(env_value "$1")"; printf '%s' "${v:-$2}"; }
DIR="$(from_env LAMAALAM_BACKUP_DIR /var/backups/lamaalam)"
RECIPIENTS="$(from_env LAMAALAM_BACKUP_RECIPIENTS '')"
KEEP_DAYS="$(from_env LAMAALAM_BACKUP_KEEP_DAYS 30)"
COPY_CMD="$(from_env LAMAALAM_BACKUP_COPY_CMD '')"

[ -n "$RECIPIENTS" ] && [ -s "$RECIPIENTS" ] || die "LAMAALAM_BACKUP_RECIPIENTS : fichier de clés publiques age absent (voir BACKUP.md)"
grep -q '^age1' "$RECIPIENTS" || die "$RECIPIENTS ne contient aucune clé publique age (age1…)"
if grep -q 'AGE-SECRET-KEY' "$RECIPIENTS"; then
  die "$RECIPIENTS contient une clé SECRÈTE : seule la clé publique doit être sur le serveur"
fi

umask 077
mkdir -p "$DIR"
exec 9>"$DIR/.backup.lock"
flock -n 9 || die "une sauvegarde est déjà en cours"

STAMP="$(date -u +%Y%m%d-%H%M%S)"
NAME="lamaalam-$STAMP"
WORK="$(mktemp -d "$DIR/.work-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
START=$(date +%s)

compose ps --status running --services | grep -qx db || die "le service db n'est pas démarré"

# 1. Base d'abord, fichiers ensuite : aucun fichier n'est jamais effacé physiquement, donc
#    chaque fiche de la base retrouve son fichier (un envoi pendant la sauvegarde ne donne
#    au pire qu'un fichier en trop, sans fiche).
log "Base de données"
compose exec -T db pg_dump -U lamaalam_owner -d lamaalam -Fc --no-password > "$WORK/db.dump"
[ -s "$WORK/db.dump" ] || die "export de la base vide"

log "Fichiers"
docker run --rm --network none -v "${PROJECT}_files-data:$FILES_PATH:ro" --entrypoint tar "$IMAGE" \
  -C "$FILES_PATH" -cf - . > "$WORK/files.tar"

cp "$ENV_FILE" "$WORK/env.secret"

REV="$(compose exec -T db psql -U lamaalam_owner -d lamaalam -tAc 'SELECT version_num FROM alembic_version' | tr -d '[:space:]')"
COUNTS="$(compose exec -T db psql -U lamaalam_owner -d lamaalam -tA -F ' ' -c \
  "SELECT (SELECT count(*) FROM organizations), (SELECT count(*) FROM users), (SELECT count(*) FROM projects), (SELECT count(*) FROM files)" 2>/dev/null || echo '? ? ? ?')"
read -r N_ORG N_USERS N_PROJECTS N_FILES <<<"$COUNTS"
{
  echo "format=1"
  echo "created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "schema_revision=$REV"
  echo "code_revision=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo inconnu)"
  echo "organizations=$N_ORG"
  echo "users=$N_USERS"
  echo "projects=$N_PROJECTS"
  echo "files=$N_FILES"
} > "$WORK/manifest.txt"
(cd "$WORK" && sha256sum db.dump files.tar env.secret manifest.txt > SHA256SUMS)

log "Chiffrement"
tar -C "$WORK" -cf - db.dump files.tar env.secret manifest.txt SHA256SUMS \
  | age -R "$RECIPIENTS" -o "$DIR/$NAME.tar.age.part"
mv "$DIR/$NAME.tar.age.part" "$DIR/$NAME.tar.age"
(cd "$DIR" && sha256sum "$NAME.tar.age" > "$NAME.tar.age.sha256")

# Conservation : archives de plus de KEEP_DAYS jours supprimées, les 7 plus récentes toujours gardées.
mapfile -t OLD < <(ls -1t "$DIR"/lamaalam-*.tar.age 2>/dev/null | tail -n +8)
for f in "${OLD[@]}"; do
  if [ -n "$(find "$f" -mtime +"$KEEP_DAYS" -print)" ]; then
    rm -f "$f" "$f.sha256"
    log "Ancienne archive supprimée : $(basename "$f")"
  fi
done

if [ -n "$COPY_CMD" ]; then
  log "Copie hors du serveur"
  $COPY_CMD "$DIR/$NAME.tar.age" "$DIR/$NAME.tar.age.sha256" || die "copie hors du serveur en échec (l'archive locale est conservée)"
fi

SIZE="$(du -h "$DIR/$NAME.tar.age" | cut -f1)"
log "Sauvegarde terminée en $(( $(date +%s) - START )) s : $DIR/$NAME.tar.age ($SIZE ; schéma $REV ; $N_PROJECTS projet(s), $N_FILES fichier(s))"
echo "$DIR/$NAME.tar.age"
