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

The current branch contains only the safe module boundary and draft contract;
it deliberately does not pretend that a cryptographic V3 codec is complete.
