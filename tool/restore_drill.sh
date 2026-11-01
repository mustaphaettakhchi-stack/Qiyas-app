#!/usr/bin/env bash
# Exercice de restauration complète, chronométré (critère de sortie du lot 1.9).
#
#   tool/restore_drill.sh            installe, remplit, sauvegarde, DÉTRUIT tout, restaure, vérifie
#   tool/restore_drill.sh --keep     laisse la pile restaurée en marche à la fin
#
# ATTENTION : supprime les conteneurs, volumes et l'image « lamaalam » de la machine.
# À lancer sur une machine d'essai ou en CI, JAMAIS sur le serveur de production.
# Prérequis : docker (compose v2), age, age-keygen, python3.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

KEEP=0
[ "${1:-}" = "--keep" ] && KEEP=1
if docker volume inspect lamaalam_db-data >/dev/null 2>&1 && [ -z "${LAMAALAM_DRILL_FORCE:-}" ]; then
  echo "Des volumes « lamaalam » existent déjà sur cette machine. Refus par prudence." >&2
  echo "Machine d'essai uniquement : relancer avec LAMAALAM_DRILL_FORCE=1 pour les détruire." >&2
  exit 1
fi

T="$(mktemp -d)"
export LAMAALAM_ENV_FILE="$T/install.env"
export LAMAALAM_BACKUP_DIR="$T/sauvegardes"
export LAMAALAM_BACKUP_RECIPIENTS="$T/cle-publique.txt"
. deploy/lib.sh
cleanup() {
  if [ "$KEEP" = 0 ]; then
    compose down -v --remove-orphans >/dev/null 2>&1 || true
  fi
  rm -rf "$T"
}
trap cleanup EXIT

secret() { python3 -c 'import secrets;print(secrets.token_urlsafe(32))'; }
fernet() { python3 -c 'import base64,os;print(base64.urlsafe_b64encode(os.urandom(32)).decode())'; }
cat > "$LAMAALAM_ENV_FILE" <<EOF
LAMAALAM_ENVIRONMENT=production
LAMAALAM_DOMAIN=localhost
LAMAALAM_PUBLIC_BASE_URL=https://localhost
LAMAALAM_OWNER_DB_PASSWORD=$(secret)
LAMAALAM_APP_DB_PASSWORD=$(secret)
LAMAALAM_JWT_SECRET=$(secret)$(secret)
LAMAALAM_TOTP_ENCRYPTION_KEY=$(fernet)
EOF
chmod 600 "$LAMAALAM_ENV_FILE"
age-keygen -o "$T/cle-privee.txt" 2>/dev/null
age-keygen -y "$T/cle-privee.txt" > "$LAMAALAM_BACKUP_RECIPIENTS"

docker_python() { compose exec -T api python - "$@" < "$ROOT/tool/drill_client.py"; }

# 1. Installation et données.
compose down -v --remove-orphans >/dev/null 2>&1 || true
deploy/deploy.sh --no-backup
EMAIL="admin-exercice@exemple.ma"
PASSWORD="Exercice-cedre-minaret-$(secret | head -c 8)"
echo "$PASSWORD" | compose exec -T api python -m app.cli create-admin --organization "Exercice" \
  --email "$EMAIL" --name "Administrateur Exercice" --password-stdin >&2
STATE="$(docker_python seed "$EMAIL" "$PASSWORD")"

# 2. Sauvegarde.
ARCHIVE="$(deploy/backup.sh)"
[ -s "$ARCHIVE" ] || die "aucune archive produite"
if age -d -i /dev/null "$ARCHIVE" >/dev/null 2>&1; then die "archive lisible sans clé privée"; fi
if tar -tf "$ARCHIVE" >/dev/null 2>&1; then die "archive non chiffrée"; fi

# 3. Machine « vierge » : plus de conteneurs, de volumes, d'image ni de fichier .env.
log "Destruction complète (conteneurs, volumes, image, .env)"
compose down -v --remove-orphans >/dev/null 2>&1
docker image rm -f "$IMAGE" >/dev/null
mv "$LAMAALAM_ENV_FILE" "$T/env-detruit"
docker volume inspect lamaalam_db-data >/dev/null 2>&1 && die "volume de base encore présent"

# 4. Restauration chronométrée, puis vérifications fonctionnelles.
R0=$(date +%s)
deploy/restore.sh "$ARCHIVE" --identity "$T/cle-privee.txt" --yes
R1=$(date +%s)
RESULT="$(docker_python verify "$STATE")"
echo "$RESULT" | grep -q '"ok": true' || die "vérification après restauration : $RESULT"

# 5. Une clé privée erronée est refusée sans rien toucher.
age-keygen -o "$T/autre-cle.txt" 2>/dev/null
if deploy/restore.sh "$ARCHIVE" --identity "$T/autre-cle.txt" --yes >/dev/null 2>&1; then
  die "restauration acceptée avec une mauvaise clé"
fi
compose ps --status running --services | grep -qx api || die "la pile a été arrêtée par une restauration refusée"

echo "EXERCICE RÉUSSI : restauration complète sur machine vierge en $((R1 - R0)) s (image reconstruite comprise) ; vérification : $RESULT"
