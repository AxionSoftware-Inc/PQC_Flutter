# antiQ RBAC plugin

Enable only for tenants that need job-title hierarchy:

```bash
ANTIQ_BACKEND_PLUGINS=rbac
```

Core chat, crypto, recovery and device APIs do not import this package.

An owner or admin can create job roles with a rank (`1` is highest) and one
visibility rule:

- `all` — can see every member;
- `lower` — can see their own rank and lower ranks;
- `self` — can see only themselves.

API routes are mounted only when enabled at `/api/rbac/`. Role assignment is
always server-authorized; a client cannot grant itself an elevated role.
