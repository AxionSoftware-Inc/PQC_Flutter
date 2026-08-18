# SDK release profiles

The Flutter host selects one writer profile at startup through the
compile-time `SDK_RELEASE` define. All profiles keep every supported historical
decoder enabled; only one private-message writer and one group-message writer
are active.

| Profile | Private/group message writer | Group-key envelope writer |
| --- | --- | --- |
| `v2` | `pqc:v2:` / `group:v2:` | `group-wrap:pqc:v2:` |
| `v25` | `pqc:v2:` / `group:v2:` | `group-wrap:pqc:v2.5:` when the server advertises dual compatibility |
| `v3` | `pqc:v3:` / `group:v3:` | V2 envelope remains the compatibility default |

Run a profile locally with:

```bash
flutter run --dart-define=SDK_RELEASE=v2
flutter run --dart-define=SDK_RELEASE=v25
flutter run --dart-define=SDK_RELEASE=v3
```

The backend must advertise the matching deployment mode:

```bash
CRYPTO_PROTOCOL_MODE=v2
CRYPTO_PROTOCOL_MODE=v25
CRYPTO_PROTOCOL_MODE=v3_test
```

The app's capability gate refuses to send when the selected writer is not
readable and writable by the remote API. This protects both private and group
chat from silently falling back to another protocol.
