#!/usr/bin/env bash
set -euo pipefail

# Run this on the server from the release checkout. The explicit PostgreSQL
# environment is intentional: migrations must never silently target SQLite.
ROOT="${ROOT:-/root/pqc-chat-app/current}"
ENV_FILE="${ENV_FILE:-/etc/pqc-chat.env}"

if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

: "${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set through the environment file}"
cd "$ROOT"

export DB_BACKEND=postgres
export POSTGRES_DB="${POSTGRES_DB:-pqc_chat_app}"
export POSTGRES_USER="${POSTGRES_USER:-pqc_chat_app}"
export POSTGRES_HOST="${POSTGRES_HOST:-127.0.0.1}"
export POSTGRES_PORT="${POSTGRES_PORT:-5432}"
export SQLITE_PATH=""

python_bin="${PYTHON_BIN:-$ROOT/.venv/bin/python}"
"$python_bin" services/backend/manage.py check
"$python_bin" services/backend/manage.py migrate --noinput
systemctl restart pqc-chat.service
systemctl is-active --quiet pqc-chat.service
curl --fail --silent --show-error http://127.0.0.1:8020/api/crypto/protocols >/dev/null
curl --fail --silent --show-error http://127.0.0.1:8020/api/health >/dev/null
echo "Backend deployed and healthy."
