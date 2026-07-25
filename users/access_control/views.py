from django.db import transaction
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from users.access_control.catalog import (
    AccessPermission,
    BUILT_IN_ROLE_PERMISSIONS,
    permission_catalog,
)
from users.access_control.policy import WorkspaceAccessPolicy
from users.access_control.serializers import (
    WorkspaceAccessRoleAssignmentSerializer,
    WorkspaceAccessRoleAssignmentWriteSerializer,
    WorkspaceAccessRoleSerializer,
    WorkspaceAccessRoleWriteSerializer,
)
from users.models import (
    Workspace,
    WorkspaceAccessRole,
    WorkspaceAccessRoleAssignment,
    WorkspaceMember,
)
from users.roles import CORPORATE_ROLE_DESCRIPTIONS, CORPORATE_ROLE_ORDER


class WorkspaceAccessView(APIView):
    def get_workspace(self, request):
        requested_id = request.headers.get('X-Workspace-Id', '').strip()
        memberships = WorkspaceMember.objects.filter(
            organization_member__user=request.user,
            organization_member__is_active=True,
            is_active=True,
        )
        if requested_id.isdigit():
            member = memberships.filter(workspace_id=int(requested_id)).first()
        else:
            member = memberships.order_by(
                '-workspace__is_default',
                'workspace_id',
            ).first()
        return None if member is None else member.workspace

    def require(self, request, permission_code):
        workspace = self.get_workspace(request)
        if workspace is None:
            return None, Response(
                {'detail': 'Active workspace was not found for this user.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        if not WorkspaceAccessPolicy.allows(
            user=request.user,
            workspace=workspace,
            permission_code=permission_code,
        ):
            return None, Response(
                {
                    'detail': 'This action is not allowed.',
                    'required_permission': permission_code,
                },
                status=status.HTTP_403_FORBIDDEN,
            )
        return workspace, None


class PermissionCatalogView(WorkspaceAccessView):
    def get(self, request):
        workspace, error = self.require(request, AccessPermission.ROLES_VIEW)
        if error is not None:
            return error
        return Response(
            {
                'workspace_id': workspace.id,
                'permissions': permission_catalog(),
                'built_in_roles': [
                    {
                        'key': role.value,
                        'name': role.label,
                        'description': CORPORATE_ROLE_DESCRIPTIONS[role],
                        'permissions': sorted(BUILT_IN_ROLE_PERMISSIONS[role]),
                    }
                    for role in CORPORATE_ROLE_ORDER
                ],
            }
        )


class AccessRoleListCreateView(WorkspaceAccessView):
    def get(self, request):
        workspace, error = self.require(request, AccessPermission.ROLES_VIEW)
        if error is not None:
            return error
        roles = WorkspaceAccessRole.objects.filter(workspace=workspace).prefetch_related(
            'permissions'
        )
        return Response(WorkspaceAccessRoleSerializer(roles, many=True).data)

    @transaction.atomic
    def post(self, request):
        workspace, error = self.require(request, AccessPermission.ROLES_MANAGE)
        if error is not None:
            return error
        serializer = WorkspaceAccessRoleWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if WorkspaceAccessRole.objects.filter(
            workspace=workspace,
            key=serializer.validated_data['key'],
        ).exists():
            return Response(
                {'detail': 'A role with this key already exists.'},
                status=status.HTTP_409_CONFLICT,
            )
        role = WorkspaceAccessRole(
            workspace=workspace,
            key=serializer.validated_data['key'],
            name=serializer.validated_data['name'],
            created_by=request.user,
        )
        serializer.apply_to(role=role)
        role.refresh_from_db()
        return Response(
            WorkspaceAccessRoleSerializer(role).data,
            status=status.HTTP_201_CREATED,
        )


class AccessRoleDetailView(WorkspaceAccessView):
    def get_role(self, workspace, role_id):
        return (
            WorkspaceAccessRole.objects.filter(
                workspace=workspace,
                id=role_id,
            )
            .prefetch_related('permissions')
            .first()
        )

    @transaction.atomic
    def patch(self, request, role_id):
        workspace, error = self.require(request, AccessPermission.ROLES_MANAGE)
        if error is not None:
            return error
        role = self.get_role(workspace, role_id)
        if role is None:
            return Response(
                {'detail': 'Role not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        serializer = WorkspaceAccessRoleWriteSerializer(
            data=request.data,
            partial=True,
        )
        serializer.is_valid(raise_exception=True)
        next_key = serializer.validated_data.get('key', role.key)
        if WorkspaceAccessRole.objects.filter(
            workspace=workspace,
            key=next_key,
        ).exclude(id=role.id).exists():
            return Response(
                {'detail': 'A role with this key already exists.'},
                status=status.HTTP_409_CONFLICT,
            )
        serializer.apply_to(role=role)
        role.refresh_from_db()
        return Response(WorkspaceAccessRoleSerializer(role).data)

    @transaction.atomic
    def delete(self, request, role_id):
        workspace, error = self.require(request, AccessPermission.ROLES_MANAGE)
        if error is not None:
            return error
        role = self.get_role(workspace, role_id)
        if role is None:
            return Response(
                {'detail': 'Role not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        role.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class AccessRoleAssignmentListCreateView(WorkspaceAccessView):
    def get(self, request):
        workspace, error = self.require(request, AccessPermission.ROLES_VIEW)
        if error is not None:
            return error
        assignments = WorkspaceAccessRoleAssignment.objects.filter(
            workspace_member__workspace=workspace,
            role__workspace=workspace,
        ).select_related(
            'role',
            'workspace_member__organization_member',
        )
        return Response(
            WorkspaceAccessRoleAssignmentSerializer(assignments, many=True).data
        )

    @transaction.atomic
    def post(self, request):
        workspace, error = self.require(request, AccessPermission.ROLES_MANAGE)
        if error is not None:
            return error
        serializer = WorkspaceAccessRoleAssignmentWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        member = WorkspaceMember.objects.filter(
            id=serializer.validated_data['workspace_member_id'],
            workspace=workspace,
            is_active=True,
            organization_member__is_active=True,
        ).first()
        role = WorkspaceAccessRole.objects.filter(
            id=serializer.validated_data['role_id'],
            workspace=workspace,
            is_active=True,
        ).first()
        if member is None or role is None:
            return Response(
                {'detail': 'Role or workspace member not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        assignment, created = WorkspaceAccessRoleAssignment.objects.get_or_create(
            workspace_member=member,
            role=role,
            defaults={'assigned_by': request.user},
        )
        return Response(
            WorkspaceAccessRoleAssignmentSerializer(assignment).data,
            status=status.HTTP_201_CREATED if created else status.HTTP_200_OK,
        )


class AccessRoleAssignmentDetailView(WorkspaceAccessView):
    @transaction.atomic
    def delete(self, request, assignment_id):
        workspace, error = self.require(request, AccessPermission.ROLES_MANAGE)
        if error is not None:
            return error
        assignment = WorkspaceAccessRoleAssignment.objects.filter(
            id=assignment_id,
            workspace_member__workspace=workspace,
            role__workspace=workspace,
        ).first()
        if assignment is None:
            return Response(
                {'detail': 'Role assignment not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        assignment.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class MyAccessSnapshotView(WorkspaceAccessView):
    def get(self, request):
        workspace = self.get_workspace(request)
        if workspace is None:
            return Response(
                {'detail': 'Active workspace was not found for this user.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        snapshot = WorkspaceAccessPolicy.snapshot(
            user=request.user,
            workspace=workspace,
        )
        if snapshot is None:
            return Response(
                {'detail': 'Active membership was not found.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        return Response(
            {
                'workspace_id': snapshot.workspace_id,
                'workspace_member_id': snapshot.member_id,
                'built_in_role': snapshot.built_in_role,
                'custom_roles': snapshot.custom_roles,
                'permissions': sorted(snapshot.permissions),
            }
        )
