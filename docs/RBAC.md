# antiQ universal RBAC

RBAC is workspace-scoped and deliberately separate from a person's visible
job title.

## Stable layers

- `CorporateRole`: built-in Owner, Admin, Manager, Member compatibility roles.
- `WorkspaceAccessRole`: a company-defined role such as Security Auditor.
- `WorkspaceAccessRolePermission`: stable permission codes attached to a role.
- `WorkspaceAccessRoleAssignment`: assigns a custom role to a workspace member.
- `WorkspaceAccessPolicy`: the only authorization evaluator API code should use.

Custom roles add permissions to the built-in role. An unknown permission always
fails closed. There is intentionally no permission for reading encrypted
message plaintext.

## API

All endpoints require authentication and use `X-Workspace-Id`.

- `GET /api/rbac/catalog`
- `GET|POST /api/rbac/roles`
- `PATCH|DELETE /api/rbac/roles/{id}`
- `GET|POST /api/rbac/assignments`
- `DELETE /api/rbac/assignments/{id}`
- `GET /api/rbac/me`

Only callers with `roles.manage` may mutate roles and assignments. Existing
member invitation, role update, and deactivation endpoints also use the central
policy.

## Adding a permission

1. Add the stable code and definition in `users/access_control/catalog.py`.
2. Decide which built-in roles receive it.
3. Enforce it through `WorkspaceAccessPolicy.allows`.
4. Add API denial and success tests.
5. Never rename a deployed code; add a new code and migrate assignments.
