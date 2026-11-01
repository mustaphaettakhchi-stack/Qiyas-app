#!/usr/bin/env bash
# Déploiement ou mise à jour du serveur LAMAALAM (docs/DEPLOYMENT.md).
#
#   deploy/deploy.sh              construit l'image, sauvegarde si une base existe, démarre
#   deploy/deploy.sh --no-backup  sans sauvegarde préalable (première installation)
#
# La version déployée est celle du dossier courant (git checkout de la version voulue
# au préalable). Aucun service payant, aucune publication sur un magasin d'applications.
. "$(dirname "$0")/lib.sh"

BACKUP=1
for a in "$@"; do
  case "$a" in
    --no-backup) BACKUP=0 ;;
    *) die "option inconnue : $a" ;;
  esac
done

need docker
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 requis (docker compose)"
check_env

START=$(date +%s)
build_image

# Sauvegarde avant mise à jour, si une base existe déjà (les migrations ne s'annulent pas
# toujours sans perte : la sauvegarde est le vrai retour arrière).
if [ "$BACKUP" = 1 ] && docker volume inspect "${PROJECT}_db-data" >/dev/null 2>&1; then
  if compose ps --status running --services 2>/dev/null | grep -qx db; then
    log "Sauvegarde avant mise à jour"
    "$ROOT/deploy/backup.sh"
  else
    die "une base existe mais le service db est arrêté : démarrez-le (docker compose up -d db) ou passez --no-backup en connaissance de cause"
  fi
fi

log "Démarrage (migrations de la base comprises)"
compose up -d --no-build --remove-orphans >&2
wait_healthy
REV="$(compose exec -T db psql -U lamaalam_owner -d lamaalam -tAc 'SELECT version_num FROM alembic_version' | tr -d '[:space:]')"
log "Déploiement terminé en $(( $(date +%s) - START )) s — schéma de base $REV — https://$(env_value LAMAALAM_DOMAIN)"
