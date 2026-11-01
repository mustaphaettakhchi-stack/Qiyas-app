#!/usr/bin/env bash
# Test de bout en bout application ↔ serveur sur une base PostgreSQL jetable.
# Usage : LAMAALAM_TEST_DATABASE_URL=postgresql+psycopg://… tool/integration_test.sh
# ATTENTION : la base indiquée est entièrement effacée.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${LAMAALAM_TEST_DATABASE_URL:?base de test à indiquer}"
PY="${PYTHON:-python3}"
PORT="${LAMAALAM_IT_PORT:-8765}"

export LAMAALAM_DATABASE_URL="$LAMAALAM_TEST_DATABASE_URL"
export LAMAALAM_ENVIRONMENT=test
export LAMAALAM_FILES_DIR="$(mktemp -d)"
export LAMAALAM_JWT_SECRET="$($PY -c 'import secrets;print(secrets.token_urlsafe(48))')"
export LAMAALAM_TOTP_ENCRYPTION_KEY="$($PY -c 'from cryptography.fernet import Fernet;print(Fernet.generate_key().decode())')"
export LAMAALAM_IT_ADMIN_EMAIL="admin-$(date +%s)@exemple.ma"
export LAMAALAM_IT_ADMIN_PASSWORD="Portail-sable-minaret-ocre-58"
export LAMAALAM_IT_API_URL="http://127.0.0.1:$PORT"

pushd backend >/dev/null
$PY - <<'PYEOF'
import os
from sqlalchemy import create_engine, text
e = create_engine(os.environ["LAMAALAM_DATABASE_URL"])
with e.begin() as c:
    c.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
PYEOF
$PY -m alembic upgrade head >/dev/null
echo "$LAMAALAM_IT_ADMIN_PASSWORD" | $PY -m app.cli create-admin --organization "Organisation de test" \
  --email "$LAMAALAM_IT_ADMIN_EMAIL" --name "Admin Test" --password-stdin
$PY -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" --log-level warning &
SERVER=$!
popd >/dev/null
trap 'kill $SERVER 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do
  curl -fs "$LAMAALAM_IT_API_URL/api/v1/health" >/dev/null && break
  sleep 0.2
done
flutter test test/integration/
