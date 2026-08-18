# V3 engine architecture

V3 is developed in isolated modules and is not enabled by default.

```text
V3EngineManager
  ├── V3Encoder       (write path, disabled until approval)
  ├── V3Decoder       (read path, compatibility tested)
  ├── crypto adapter  (PQC primitives only)
  ├── key adapter     (key lifecycle and recovery)
  ├── storage adapter  (persistence, no UI)
  └── transport adapter (HTTP/WebSocket, no crypto policy)
```

Rules:

* V2 remains the production writer and decoder.
* V3 cannot emit a payload until compatibility approval opens its write gate.
* V2 decoder is never removed when V3 becomes the writer.
* Every V3 module must have protocol vectors, migration tests, reinstall tests,
  cross-device tests and a server capability handshake before the gate opens.
* The manager has no Flutter, HTTP, database or platform imports.

The cryptographic V3 codec now lives in the pure `pqc_engine_sdk` package.
`crypto_core` remains a Flutter host adapter for key lifecycle and recovery; it
must not fork or alter the SDK wire serialization.

V3 envelopes carry the sender KEM public key alongside the signing public key.
The decoder recomputes the keyset binding from both keys and the device id, so
an opaque sender binding id cannot be swapped independently of the key pair.
