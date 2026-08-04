# antiQ backend core

The backend is split into a stable core and explicit optional plugins. A plain
deployment uses only the core; it has no RBAC dependency.

## Stable core

- `backend/config`: Django settings, ASGI, error boundary and plugin loading.
- `users`: accounts, devices, workspace membership and encrypted recovery
  records.
- `chat`: encrypted payload transport, conversation metadata, attachments and
  realtime events.
- `packages/crypto_core`: client-side SDK-facing cryptographic implementation.

The server never imports a client private key and never decrypts message text.

## Optional extensions

All optional server modules live in `backend_plugins/`. The only registration
point is `ANTIQ_BACKEND_PLUGINS`, which is empty by default. For example:

```bash
ANTIQ_BACKEND_PLUGINS=rbac
```

An unknown plugin name prevents startup. That is intentional: a typo must not
silently disable access control. The RBAC package is currently only an isolated
extension point; it is not enabled and has no effect on the core API.

## Fresh-server procedure

1. Install PostgreSQL and Python 3 with `venv` support.
2. Create the database and a database user.
3. Copy `deploy/backend.env.example` to `/etc/antiq/backend.env`, set secrets,
   allowed hosts and database values, then run `chmod 600` on it.
4. Run `ENV_FILE=/etc/antiq/backend.env deploy/bootstrap_backend.sh` from the
   release checkout.
5. Place Daphne behind Nginx (or another TLS reverse proxy) and expose only the
   proxy port.

The bootstrap runs Django validation and migrations before starting any
application process. Production settings reject missing KMS, PostgreSQL,
approval policy, allowed hosts and strong secrets.

## Versioned engines

V2, V2.5 and V3 are client/SDK protocol implementations. Backend transport
stores their declared protocol metadata and capability information; it must not
contain engine-private encoder logic. New engines are introduced through the
SDK protocol registry and capability negotiation, while supported historical
decoders remain read-only.
