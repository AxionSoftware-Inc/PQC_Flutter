#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${POSTGRES_DB:-pqc_chat_app}"
DB_USER="${POSTGRES_USER:-pqc_chat_app}"
DB_PASSWORD="${POSTGRES_PASSWORD:-pqc_chat_app_dev_password}"
DB_HOST="${POSTGRES_HOST:-127.0.0.1}"
DB_PORT="${POSTGRES_PORT:-5432}"

brew services start postgresql@14 >/dev/null

psql -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}' CREATEDB;
  ELSE
    ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}' CREATEDB;
  END IF;
END
\$\$;
SQL

if ! psql -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
  createdb -O "${DB_USER}" "${DB_NAME}"
fi

cat <<EOF
Local PostgreSQL is ready.

Use these env vars for Django:
  DB_BACKEND=postgres
  POSTGRES_DB=${DB_NAME}
  POSTGRES_USER=${DB_USER}
  POSTGRES_PASSWORD=${DB_PASSWORD}
  POSTGRES_HOST=${DB_HOST}
  POSTGRES_PORT=${DB_PORT}
EOF
