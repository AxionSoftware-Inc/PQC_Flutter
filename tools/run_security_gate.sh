#!/usr/bin/env bash
set -euo pipefail

python3 tools/security_audit.py
python3 tools/audit_pub_dependencies.py
python3 -m pip_audit -r backend/requirements.txt --strict

DJANGO_ENV=production \
DJANGO_SECRET_KEY='security-gate-only-abcdefghijklmnopqrstuvwxyz-0123456789-ABCDEFGHIJKLMNOPQRSTUVWXYZ' \
DJANGO_ALLOWED_HOSTS='chat.example.invalid' \
DATABASE_URL='postgresql://audit:audit@127.0.0.1:5432/audit' \
AWS_REGION='us-east-1' \
AWS_KMS_ESCROW_KEY_ID='arn:aws:kms:us-east-1:000000000000:key/security-gate' \
python3 backend/manage.py check --deploy

flutter analyze
flutter test
