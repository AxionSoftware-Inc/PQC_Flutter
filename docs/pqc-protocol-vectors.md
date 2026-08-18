# PQC protocol vectors

These values are a cross-language compatibility fixture. Dart and Python must
produce the same canonical JSON bytes before hashing; key order and compact
separators are part of the contract.

```json
{
  "device_id": "device-vector-1",
  "kem_public_key": "a2VtLXB1YmxpYy1rZXk=",
  "signing_public_key": "c2lnbmluZy1wdWJsaWMta2V5",
  "keyset_binding_id": "g-hOJDNYj9g_YdpEXzEW58AFJniIs5zYL99-fT47bpk"
}
```

The fixture covers the V3/V2.5 keyset identity boundary. Any change to the
canonical fields or their order requires a new protocol version and migration
plan; the frozen V2 `keyset_id` remains a separate compatibility identifier.

V3 message documents also carry `sender_kem_public_key`. Decoders recompute
`keyset_binding_id` from `device_id`, that KEM public key and
`signing_public_key` before accepting the signature, preventing a sender
signing key from being rebound to another KEM key.
