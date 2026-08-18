# V3 backend rollout

The backend keeps V2 immutable and exposes V3 as a deployment capability.

`CRYPTO_PROTOCOL_MODE` defaults to `v2`. In that mode the API writes V2 while
still keeping the versioned registry isolated. A test deployment can set:

```text
CRYPTO_PROTOCOL_MODE=v3_test
```

That advertises both V2 and V3 as readable, enables V3 private/group writers,
while retaining the V2 attachment writer. V3 attachment capability is only
advertised by the separate `v3_full` mode, which enables the authenticated
chunk transfer path and must still pass the production rollout gates.
Existing V2 clients remain
able to send V2 payloads. V2 clients cannot decode V3 payloads; this is an
intentional compatibility boundary.

Production must not enable `v3_test` until the V3 app gate, server capability
negotiation, and two-device migration tests are green.

For the intermediate V2.5 group-key rollout, set
`CRYPTO_PROTOCOL_MODE=v25`. The API then accepts historical V2 envelopes and
advertises only `group-wrap:pqc:v2.5` as the new envelope writer. Message
payloads remain V2, so V2 clients and V2 message history are not disrupted.
