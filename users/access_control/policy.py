from dataclasses import dataclass

from users.access_control.catalog import (
    BUILT_IN_ROLE_PERMISSIONS,
    PERMISSIONS_BY_CODE,
)
from users.models import Workspace, WorkspaceAccessRoleAssignment, WorkspaceMember


@dataclass(frozen=True)
class WorkspaceAccessSnapshot:
    workspace_id: int
    member_id: int
    built_in_role: str
    custom_roles: tuple[str, ...]
    permissions: frozenset[str]

    def allows(self, permission_code: str) -> bool:
        return permission_code in self.permissions


class WorkspaceAccessPolicy:
    """Single authorization entry point for API and future admin UI code."""

    @staticmethod
    def snapshot(*, user, workspace: Workspace) -> WorkspaceAccessSnapshot | None:
        if not getattr(user, 'is_authenticated', False):
            return None
        member = (
            WorkspaceMember.objects.select_related('organization_member')
            .filter(
                workspace=workspace,
                organization_member__user=user,
                organization_member__is_active=True,
                is_active=True,
            )
            .first()
        )
        if member is None:
            return None

        permissions = set(BUILT_IN_ROLE_PERMISSIONS.get(member.role, ()))
        assignments = (
            WorkspaceAccessRoleAssignment.objects.filter(
                workspace_member=member,
                role__workspace=workspace,
                role__is_active=True,
            )
            .select_related('role')
            .prefetch_related('role__permissions')
        )
        custom_roles = []
        for assignment in assignments:
            custom_roles.append(assignment.role.key)
            permissions.update(
                item.permission_code for item in assignment.role.permissions.all()
            )
        return WorkspaceAccessSnapshot(
            workspace_id=workspace.id,
            member_id=member.id,
            built_in_role=member.role,
            custom_roles=tuple(sorted(custom_roles)),
            permissions=frozenset(permissions),
        )

    @staticmethod
    def allows(*, user, workspace: Workspace, permission_code: str) -> bool:
        if permission_code not in PERMISSIONS_BY_CODE:
            return False
        if getattr(user, 'is_superuser', False):
            return True
        snapshot = WorkspaceAccessPolicy.snapshot(user=user, workspace=workspace)
        return snapshot is not None and snapshot.allows(permission_code)
