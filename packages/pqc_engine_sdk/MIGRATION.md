# Application migration

The Flutter application consumes this package through adapters. UI, file I/O
and networking remain outside the engine package; only key material, trust
records and byte/file adapters cross the boundary.

## Recommended sequence

1. Pin the package to an immutable Git tag for external consumers.
2. Implement `PqcKeyRepository` over the application's secure storage.
3. Import the current keyset and every historical V2 keyset without changing
   bytes or keyset ids.
4. Build the trusted signing-key map from current and historical device
   records.
5. Run the SDK decoder beside the frozen production decoder and compare
   results during migration.
6. Exercise reinstall, relogin, account switch, key rotation, device revoke
   and group rekey recovery tests.
7. Enable the writer only after the server advertises all required
   capabilities.
8. Roll back by closing the writer gate; keep the decoder registered.

For the V2.5 group-epoch candidate, require the backend capability response to
contain `group-wrap:pqc:v2.5` in both its readable and writable group-envelope
prefix sets before selecting that writer. Keep `group-wrap:pqc:v2` enabled as
the historical reader during the entire rollout.

## Adapter boundaries

- API models -> `PqcDevicePublicKey`
- secure store -> `PqcKeyRepository`
- recovery endpoint -> `PqcRecoveryRepository`
- chat model -> `PqcConversation`
- backend capability response -> `PqcRemoteCapabilities`

The SDK does not migrate V2 keys into new cryptographic bytes. A future V3
engine must have its own writer and decoder while retaining this V2 decoder.
The V3 wire engine and V3 attachment codec now live in this pure SDK.
`crypto_core` provides the Flutter primitive/key/file adapters and keeps the
V3 writer behind the server capability gate.
