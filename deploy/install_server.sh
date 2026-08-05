#!/usr/bin/env bash
set -euo pipefail

# One repeatable core deployment. PostgreSQL and the environment file are
# operator-owned inputs; tenant plugins remain disabled unless named there.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-/etc/antiq/backend.env}"
PUBLIC_HOST="${PUBLIC_HOST:?PUBLIC_HOST must be a domain or server IP}"
SERVICE_USER="${SERVICE_USER:-root}"
SYSTEMD_UNIT="${SYSTEMD_UNIT:-antiq.service}"
NGINX_SITE="${NGINX_SITE:-/etc/nginx/sites-available/antiq}"

if [[ $EUID -ne 0 ]]; then
  echo 'Run as root so systemd and Nginx can be configured.' >&2
  exit 1
fi
if [[ ! -r "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Start from deploy/backend.env.example." >&2
  exit 1
fi

ENV_FILE="$ENV_FILE" ROOT="$ROOT" "$ROOT/deploy/bootstrap_backend.sh"

mkdir -p "$(dirname "$NGINX_SITE")"
sed \
  -e "s|__ANTIQ_ROOT__|$ROOT|g" \
  -e "s|__ANTIQ_ENV_FILE__|$ENV_FILE|g" \
  -e "s|__ANTIQ_USER__|$SERVICE_USER|g" \
  "$ROOT/deploy/pqc-chat.service.template" \
  > "/etc/systemd/system/$SYSTEMD_UNIT"
sed -e "s|__ANTIQ_HOST__|$PUBLIC_HOST|g" \
  "$ROOT/deploy/nginx-antiq.site.template" > "$NGINX_SITE"
ln -sfn "$NGINX_SITE" "/etc/nginx/sites-enabled/antiq"

systemctl daemon-reload
systemctl enable --now "$SYSTEMD_UNIT"
nginx -t
systemctl reload nginx
curl --fail --silent --show-error http://127.0.0.1:8020/api/health >/dev/null
echo "antiQ backend core is running. Add TLS before public production use."
