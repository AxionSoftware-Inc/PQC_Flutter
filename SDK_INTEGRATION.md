# Standalone SDK integration

The frozen V2 production branch is unchanged. Integration lives on
`sdk-app-integration-v2`.

The app consumes `PQC-SDK` by immutable private Git tag. The separate
`pqc_engine_flutter_adapter` package converts app conversations, devices,
trusted signing keys, historical keysets and group epochs into SDK models.

Rollout sequence:

1. `legacy` — dependency and adapter present, runtime behavior unchanged.
2. `shadow` — compare old and SDK decoders on real devices.
3. `read` — SDK decoder authoritative, old writer retained.
4. `active` — SDK reader/writer enabled only with both independent gates.

Never merge an active-mode build based only on unit tests. Reinstall, relogin,
account switch, device rotation, server recovery and group rekey must pass on
two real devices first.
