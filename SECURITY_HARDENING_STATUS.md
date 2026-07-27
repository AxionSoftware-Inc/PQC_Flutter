# Security hardening status

Last reviewed: 2026-07-27

## Enforced controls

- Production settings are fail-closed. Production refuses to boot without a
  strong Django secret, explicit hosts, PostgreSQL, AWS region and KMS key.
- HTTPS redirect, secure cookies and one-year HSTS are enabled automatically in
  production.
- Recovery reads require all of the following:
  - an authenticated account token;
  - an active device ID;
  - a separate device-bound recovery credential;
  - either a one-use grant from fresh Google verification or a one-use
    approval from another active device.
- A login token by itself cannot fetch decrypted escrow records.
- Recovery metadata sync never returns decrypted recovery payloads.
- Mobile secret-storage failures are fail-closed. SharedPreferences fallback is
  disabled by default and cannot be enabled in release builds.
- Legacy SharedPreferences secrets are migrated into platform secure storage
  only after authenticated decryption; the fallback master key is removed when
  migration is complete.
- Recovery records use AES-256-GCM envelope encryption and production requires
  AWS KMS for DEK wrapping.
- Complete Git history is checked for high-confidence committed credentials by
  `python tools/security_audit.py`.
- Python dependencies are checked by `pip-audit`; known vulnerabilities fail
  the gate.
- Dependabot monitors Python, Dart and GitHub Actions dependencies.
- Django `check --deploy`, backend tests, Flutter analysis and Flutter tests are
  part of the security gate.

Run locally:

```bash
python -m pip install -r backend/requirements.txt
python -m pip install -r backend/requirements-security.txt
tools/run_security_gate.sh
```

## Trust-model limitation

Enterprise recovery is server-managed escrow. A database dump without KMS
permissions cannot decrypt recovery records, but the live backend with KMS
decrypt permission can recover private keysets. This is intentionally not a
zero-knowledge recovery design.

Moving to a server-blind recovery design requires a separate user-held secret,
passkey, trusted-device secret, or threshold key split. That choice changes the
product recovery contract and must not be represented as a small configuration
change.

## Mandatory external release gate

Internal tests cannot certify that no vulnerability exists. Before commercial
production, an independent party must complete and sign off:

- mobile application storage and runtime testing against OWASP MASVS;
- API authorization and recovery-flow penetration testing;
- KMS/IAM and deployment review;
- cryptographic protocol/design review;
- Android/iOS release binary and supply-chain review.

Production security approval remains incomplete until those external reports
exist and all critical/high findings are closed.
