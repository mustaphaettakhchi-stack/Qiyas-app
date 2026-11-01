# Fonctions communes aux scripts d'exploitation LAMAALAM (deploy.sh, backup.sh, restore.sh).
# À charger avec « . deploy/lib.sh » depuis la racine du dépôt.
# Aucun service payant n'est appelé : Docker, PostgreSQL, tar, sha256sum et age, en local.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${LAMAALAM_ENV_FILE:-$ROOT/.env}"
IMAGE="lamaalam-api:local"
PROJECT="lamaalam"          # nom fixé dans docker-compose.yml
FILES_PATH="/var/lib/lamaalam/files"

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*" >&2; }
die() { printf 'ERREUR : %s\n' "$*" >&2; exit 1; }

need() {
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || die "commande « $c » introuvable (voir docs/INSTALLATION.md)"; done
}

compose() {
  LAMAALAM_ENV_FILE="$ENV_FILE" docker compose --project-directory "$ROOT" -f "$ROOT/docker-compose.yml" \
    --env-file "$ENV_FILE" "$@"
}

# Valeur d'une variable du fichier .env (sans l'exécuter).
env_value() {
  local v
  v="$(grep -E "^$1=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- || true)"
  printf '%s' "$v"
}

check_env() {
  [ -f "$ENV_FILE" ] || die "fichier $ENV_FILE absent (copier .env.example, voir docs/INSTALLATION.md)"
  local mode
  mode="$(stat -c %a "$ENV_FILE")"
  [ "$mode" = "600" ] || [ "$mode" = "400" ] || die "$ENV_FILE doit être lisible par son seul propriétaire : chmod 600 $ENV_FILE"
  local k
  for k in LAMAALAM_DOMAIN LAMAALAM_PUBLIC_BASE_URL LAMAALAM_OWNER_DB_PASSWORD LAMAALAM_APP_DB_PASSWORD \
           LAMAALAM_JWT_SECRET LAMAALAM_TOTP_ENCRYPTION_KEY; do
    [ -n "$(env_value "$k")" ] || die "$k est vide dans $ENV_FILE"
  done
  [ "$(env_value LAMAALAM_ENVIRONMENT)" = "production" ] || die "LAMAALAM_ENVIRONMENT doit valoir production"
}

# Construit l'image de l'API. LAMAALAM_BUILD_CA : certificat d'autorité facultatif (réseau
# d'entreprise qui inspecte le HTTPS), transmis comme secret de construction, jamais copié.
build_image() {
  local args=(build -t "$IMAGE")
  if [ -n "${LAMAALAM_BUILD_CA:-}" ]; then
    args+=(--secret "id=pip_ca,src=$LAMAALAM_BUILD_CA")
  fi
  [ -n "${LAMAALAM_BUILD_NETWORK:-}" ] && args+=(--network "$LAMAALAM_BUILD_NETWORK")
  log "Construction de l'image $IMAGE"
  docker "${args[@]}" "$ROOT/backend" >&2
}

wait_healthy() {
  local i
  for i in $(seq 1 60); do
    if compose exec -T api python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/v1/health', timeout=4).status == 200 else 1)" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  compose logs --tail 50 api migrate >&2 || true
  die "l'API ne répond pas après 2 minutes"
}

wait_db() {
  # Par TCP : pendant son initialisation, l'image postgres n'écoute que sur la socket locale ;
  # TCP prêt = scripts d'initialisation (rôle lamaalam_app) terminés.
  local i
  for i in $(seq 1 60); do
    compose exec -T db pg_isready -h 127.0.0.1 -U lamaalam_owner -d lamaalam >/dev/null 2>&1 && return 0
    sleep 2
  done
  die "PostgreSQL ne répond pas après 2 minutes"
}
