# PQC Engine Flutter Adapter

Application-only bridge between the frozen V2 Flutter chat models/storage and
the standalone `pqc_engine_sdk`. It contains no UI.

## Migration modes

- `legacy` (default): frozen app reader and writer; SDK is not executed.
- `shadow`: frozen reader/writer remain authoritative while SDK decode results
  are compared without recording plaintext.
- `read`: SDK decoder is authoritative; frozen writer remains active.
- `active`: SDK reader and writer are authoritative.

Build examples:

```sh
flutter build apk --release --dart-define=SDK_V2_MODE=shadow

flutter build apk --release \
  --dart-define=SDK_V2_MODE=active \
  --dart-define=SDK_V2_WRITER_ENABLED=true \
  --dart-define=SDK_V2_COMPATIBILITY_APPROVED=true
```

Active mode fails closed unless both independent gates are present.

## Boundaries

- Existing `KeyMaterialRegistry` remains the source of current and historical
  private keys.
- Existing enterprise recovery remains responsible for reinstall recovery.
- Existing `GroupKeyProvider` remains responsible for group epoch envelopes.
- The SDK performs V2 message and attachment cryptography.
- The adapter never reports plaintext, payloads or keys in shadow health data.
