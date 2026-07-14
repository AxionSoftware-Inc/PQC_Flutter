# Protocol versioning rules

The protocol version is the wire format, not the app version. The current
wire format is v2 (`pqc:v2:` for private messages and `group:v2:` for groups).
The v2 and v2.5 app releases therefore share one decoder and one encoder.
They must not be duplicated: two implementations of the same format would
eventually diverge.

## Adding a new engine

1. Add a new immutable protocol contract and codec (for example v3).
2. Register the new format in `PayloadFormatRegistry` with
   `decryptSupported: true` and `writeEnabled: true`.
3. Change the old v2 descriptor to `decryptSupported: true` and
   `writeEnabled: false` only in the release that actually switches writers.
4. Keep the old decoder and its tests forever (or until an explicitly
   versioned data-retention policy says otherwise).
5. Ensure exactly one private writer and one group writer. Startup validation
   fails if zero or multiple writers are registered.
6. Add a compatibility test proving old payloads still decode while new
   payloads use only the new writer.

Never infer the writer from the first decoder that matches a payload. Readers
and writers are deliberately separate in `ProtocolVersionManager`.

## What is frozen now

The v2 decoder/encoder is the only active production pair. v2.5 is an app and
engine hardening release on the same v2 wire contract, not a new protocol.
Therefore no v2.5 decoder fork should be created.
