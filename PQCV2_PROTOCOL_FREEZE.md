# PQCv2 protocol freeze

This document is the release gate for the v2 engine. New writers must not be
added to v2; any wire change requires v3.

## Frozen identifiers

- Private message prefix: `pqc:v2:`
- Group message prefix: `group:v2:`
- Group key envelope prefix: `group-wrap:pqc:v2:`
- Private algorithm: `ml-kem-768+a256gcm+ml-dsa-65`
- Group algorithm: `a256gcm+group-ml-kem-768`
- Group envelope algorithm: `group-ml-kem-768-aesgcm-v2`
- Attachment cipher: `attachment:v2`
- Recovery schema: `enterprise-recovery-manifest`, revision `2`

The canonical Dart constants live in
`packages/crypto_core/lib/src/crypto/durability/v2_protocol_contract.dart`.
The backend capability endpoint is `GET /api/crypto/protocols`; clients must
check it before creating a new message or uploading an attachment.

## Release gates

1. `flutter analyze packages/crypto_core/lib packages/chat_core/lib lib/main.dart`
2. All crypto durability, private-message, group-key, attachment, backup, and
   protocol-contract tests pass.
3. The backend capability contract test passes.
4. `git diff --check` is clean.

Historical payloads are read-only compatibility inputs. They are never selected
as writers. A protocol or cryptographic field change belongs in v3 and must be
introduced with a new contract, fixtures, and migration tests.
