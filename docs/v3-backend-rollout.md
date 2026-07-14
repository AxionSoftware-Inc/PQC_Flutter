# V3 backend rollout

The backend keeps V2 immutable and exposes V3 as a deployment capability.

`CRYPTO_PROTOCOL_MODE` defaults to `v2`. In that mode the API writes V2 while
still keeping the versioned registry isolated. A test deployment can set:

```text
CRYPTO_PROTOCOL_MODE=v3_test
```

That advertises both V2 and V3 as readable, enables V3 private/group writers,
and advertises attachment cipher `attachment:v3`. Existing V2 clients remain
able to send V2 payloads. V2 clients cannot decode V3 payloads; this is an
intentional compatibility boundary.

Production must not enable `v3_test` until the V3 app gate, server capability
negotiation, and two-device migration tests are green.
