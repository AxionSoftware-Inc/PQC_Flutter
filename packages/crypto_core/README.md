# antiQ Crypto Core

`crypto_core` is the engine package used by antiQ clients. Application UI,
OAuth/login screens and Django transport are deliberately outside this package.

## Public protocol API

SDK consumers should import only:

```dart
import 'package:crypto_core/antiq_protocol_sdk.dart';
```

```dart
final protocol = AntiQProtocolSdk.v25();
print(protocol.release.releaseId);    // 2.5.0
print(protocol.release.wireProtocol); // v2
```

V2.5 has a distinct release identifier but preserves the immutable V2 wire
format. V3 uses its own writer profile and cannot be opened for writing until
the host has completed capability negotiation and explicit approval.

## Boundary rule

- The protocol API owns version selection, compatibility readers and V3 writer
  gating.
- A host owns UI, HTTP, authentication and platform secure-storage adapters.
- Historical decoder support must remain enabled after the matching encoder is
  retired.

`crypto_core.dart` remains a compatibility export for the existing Flutter app.
New integrations should use the narrow `antiq_protocol_sdk.dart` entry point.
