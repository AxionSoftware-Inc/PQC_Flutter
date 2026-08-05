from django.db import transaction
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import OrganizationMember, WorkspaceMember

from .models import JobRole, JobRoleAssignment
from .serializers import AssignmentWriteSerializer, JobRoleAssignmentSerializer, JobRoleSerializer


def _workspace(request):
    raw = request.headers.get('X-Workspace-Id', '').strip()
    members = WorkspaceMember.objects.select_related('workspace', 'organization_member').filter(
        organization_member__user=request.user, organization_member__is_active=True, is_active=True,
    )
    return members.filter(workspace_id=raw).first() if raw.isdigit() else members.order_by('-workspace__is_default', 'workspace_id').first()


def _admin(membership):
    return membership and membership.role in {OrganizationMember.Role.OWNER, OrganizationMember.Role.ADMIN}


def _visible_members(membership):
    base = WorkspaceMember.objects.select_related('organization_member__user').filter(workspace=membership.workspace, is_active=True, organization_member__is_active=True)
    if _admin(membership):
        return base
    own = JobRoleAssignment.objects.select_related('role').filter(workspace_member=membership).first()
    if own is None or own.role is None or own.role.visibility == JobRole.Visibility.SELF:
        return base.filter(id=membership.id)
    if own.role.visibility == JobRole.Visibility.ALL:
        return base
    ids = JobRoleAssignment.objects.filter(role__workspace=membership.workspace, role__rank__gte=own.role.rank, role__is_active=True).values_list('workspace_member_id', flat=True)
    return base.filter(id__in=ids) | base.filter(id=membership.id)


class RbacMeView(APIView):
    def get(self, request):
        membership = _workspace(request)
        if not membership:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        assignment = JobRoleAssignment.objects.select_related('role').filter(workspace_member=membership).first()
        return Response({'workspace_id': membership.workspace_id, 'is_admin': _admin(membership), 'assignment': JobRoleAssignmentSerializer(assignment).data if assignment else None})


class RoleListCreateView(APIView):
    def get(self, request):
        membership = _workspace(request)
        if not membership:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        return Response(JobRoleSerializer(JobRole.objects.filter(workspace=membership.workspace), many=True).data)

    def post(self, request):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        serializer = JobRoleSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        role = serializer.save(workspace=membership.workspace)
        return Response(JobRoleSerializer(role).data, status=status.HTTP_201_CREATED)


class RoleDetailView(APIView):
    def patch(self, request, role_id):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        role = JobRole.objects.filter(id=role_id, workspace=membership.workspace).first()
        if not role:
            return Response({'detail': 'Role not found.'}, status=404)
        serializer = JobRoleSerializer(role, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        return Response(JobRoleSerializer(serializer.save()).data)

    def delete(self, request, role_id):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        deleted, _ = JobRole.objects.filter(id=role_id, workspace=membership.workspace).delete()
        return Response(status=204 if deleted else 404)


class MemberListView(APIView):
    def get(self, request):
        membership = _workspace(request)
        if not membership:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        members = _visible_members(membership).order_by('organization_member__user__first_name', 'id')
        assignments = {item.workspace_member_id: item for item in JobRoleAssignment.objects.select_related('role', 'workspace_member__organization_member__user').filter(workspace_member__in=members)}
        payload = []
        for item in members:
            assignment = assignments.get(item.id)
            payload.append(JobRoleAssignmentSerializer(assignment).data if assignment else {'member_id': item.id, 'user_id': item.organization_member.user_id, 'display_name': item.organization_member.user.first_name or item.organization_member.user.username, 'role': None})
        return Response(payload)


class MemberAssignmentView(APIView):
    @transaction.atomic
    def put(self, request, member_id):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        target = WorkspaceMember.objects.filter(id=member_id, workspace=membership.workspace, is_active=True).first()
        if not target:
            return Response({'detail': 'Workspace member not found.'}, status=404)
        serializer = AssignmentWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        role_id = serializer.validated_data.get('role_id')
        role = JobRole.objects.filter(id=role_id, workspace=membership.workspace, is_active=True).first() if role_id else None
        if role_id and not role:
            return Response({'detail': 'Role not found.'}, status=404)
        assignment, _ = JobRoleAssignment.objects.update_or_create(workspace_member=target, defaults={'role': role, 'assigned_by': request.user})
        return Response(JobRoleAssignmentSerializer(assignment).data)
