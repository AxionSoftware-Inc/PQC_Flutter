#!/usr/bin/env bash
set -euo pipefail

python3 tools/security_audit.py
python3 tools/audit_pub_dependencies.py

if [[ -n "${PIP_AUDIT_BIN:-}" ]]; then
  "$PIP_AUDIT_BIN" -r services/backend/requirements.txt --strict
elif command -v pip-audit >/dev/null 2>&1; then
  pip-audit -r services/backend/requirements.txt --strict
elif python3 -c 'import pip_audit' >/dev/null 2>&1; then
  python3 -m pip_audit -r services/backend/requirements.txt --strict
else
  echo 'pip-audit is required for the security gate. Install it or set PIP_AUDIT_BIN.' >&2
  exit 1
fi

DJANGO_ENV=production \
DJANGO_SECRET_KEY='security-gate-only-abcdefghijklmnopqrstuvwxyz-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ' \
DJANGO_ALLOWED_HOSTS='chat.example.invalid' \
DATABASE_URL='postgresql://audit:audit@127.0.0.1:5432/audit' \
AWS_REGION='us-east-1' \
AWS_KMS_ESCROW_KEY_ID='arn:aws:kms:us-east-1:000000000000:key/security-gate' \
"${BACKEND_PYTHON:-services/backend/.venv/bin/python}" services/backend/manage.py check --deploy

flutter analyze
flutter test

if ! command -v dart >/dev/null 2>&1; then
  echo 'dart is required to validate the standalone PQC SDK.' >&2
  exit 1
fi
(
  cd packages/pqc_engine_sdk
  dart pub get --enforce-lockfile
  dart analyze
  dart test
)
