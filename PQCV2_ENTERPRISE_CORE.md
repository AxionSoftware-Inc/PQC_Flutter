# PQCv2 Enterprise Crypto Core

`pqc:v2`, `group:v2` and `group-wrap:pqc:v2` are the only writer formats.
PQCv1 is intentionally unsupported and historical PQCv1 messages display as
unavailable rather than attempting heuristic key selection.

## Recovery contract

- Google/OIDC account identity is the recovery owner; a device name is never
  an account identifier.
- Each private payload records immutable sender and recipient keyset IDs and
  creates an ML-KEM envelope for every active participant device.
- Each group payload records its immutable group epoch ID.  Old epochs remain
  readable when their recovery material is restored.
- On a new device, history is `recovery-pending` until the user explicitly
  restores the enterprise manifest. New messages may still be sent.
- Logout clears only session state. A user-selected "forget device" may remove
  local state; recovery remains in enterprise escrow.

## Escrow contract

The backend stores AWS KMS ciphertext plus KMS key identifier/version, payload
digest, schema version and a monotonically increasing sequence. It records
each read/write event. Set `DJANGO_ENV=production`, `AWS_REGION` and
`AWS_KMS_ESCROW_KEY_ID` in production; startup/use is rejected without KMS.
The local escrow provider is development/test only.

## Recovery authorization and revocation

In production, recovery reads require an approved `RecoveryDeviceApproval`
from a different active device. Recovery escrow records are append-only; a
revoked device's records are tombstoned rather than overwritten. Revocation
also places every affected group conversation into a pending rekey epoch, and
the server refuses further group writes until a full active-device envelope set
activates a new epoch.
