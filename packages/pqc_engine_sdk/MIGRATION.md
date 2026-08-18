# Application migration

This package is intentionally not wired into the existing Flutter application
yet. Integration should be done through adapters so that UI and networking do
not enter the engine package.

## Recommended sequence

1. Add the package by an immutable Git tag.
2. Implement `PqcKeyRepository` over the application's secure storage.
3. Import the current keyset and every historical V2 keyset without changing
   bytes or keyset ids.
4. Build the trusted signing-key map from current and historical device
   records.
5. Run the SDK as a read-only shadow decoder and compare results with the
   frozen production decoder.
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
The application-level V3 coordinator currently lives in `crypto_core`; it is
kept outside this pure SDK until its vectors and release boundary are ready.
