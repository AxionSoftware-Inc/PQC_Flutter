#!/usr/bin/env bash
set -euo pipefail

# Reproducible backend bootstrap for a fresh server or a clean checkout.
# It deliberately does not create credentials: operators provide them via the
# environment file, so configuration errors stop the rollout before the ASGI
# process is restarted.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-/etc/antiq/backend.env}"
VENV_DIR="${VENV_DIR:-$ROOT/.venv}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Missing environment file: $ENV_FILE" >&2
  echo "Start from deploy/backend.env.example and protect it with chmod 0600." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${DJANGO_ENV:?DJANGO_ENV must be set}"
: "${DJANGO_SECRET_KEY:?DJANGO_SECRET_KEY must be set}"

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --disable-pip-version-check -r "$ROOT/backend/requirements.txt"
"$VENV_DIR/bin/python" "$ROOT/backend/manage.py" check
"$VENV_DIR/bin/python" "$ROOT/backend/manage.py" migrate --noinput

echo "Backend core is prepared successfully."
echo "Start it with: $VENV_DIR/bin/daphne -b 127.0.0.1 -p 8020 config.asgi:application"
