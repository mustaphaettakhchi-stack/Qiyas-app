#!/bin/sh
# Rôle applicatif sans privilège de superutilisateur : les migrations utilisent le
# propriétaire, l'API se connecte avec ce rôle restreint (SECURITY.md §4 et §8).
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
CREATE ROLE lamaalam_app LOGIN PASSWORD '${LAMAALAM_APP_DB_PASSWORD}' NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS;
GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO lamaalam_app;
GRANT USAGE ON SCHEMA public TO lamaalam_app;
ALTER DEFAULT PRIVILEGES FOR ROLE "$POSTGRES_USER" IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO lamaalam_app;
ALTER DEFAULT PRIVILEGES FOR ROLE "$POSTGRES_USER" IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO lamaalam_app;
SQL
