#!/usr/bin/env bash
set -euo pipefail

# Run this on the server from the release checkout. The explicit PostgreSQL
# environment is intentional: migrations must never silently target SQLite.
ROOT="${ROOT:-/root/pqc-chat-app/current}"
: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set}"
cd "$ROOT"

export DB_BACKEND=postgres
export POSTGRES_DB="${POSTGRES_DB:-pqc_chat_app}"
export POSTGRES_USER="${POSTGRES_USER:-pqc_chat_app}"
export POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export SQLITE_PATH=""

python_bin="${PYTHON_BIN:-$ROOT/.venv/bin/python}"
"$python_bin" backend/manage.py check
"$python_bin" backend/manage.py migrate --noinput
systemctl restart pqc-chat.service
systemctl is-active --quiet pqc-chat.service
curl --fail --silent --show-error http://127.0.0.1:8020/api/crypto/protocols >/dev/null
echo "Backend deployed and healthy."
