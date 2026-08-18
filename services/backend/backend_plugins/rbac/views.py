from django.db import transaction
from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from uuid import uuid4

from users.models import Invitation, OrganizationMember, WorkspaceMember

from .models import JobRole, JobRoleAssignment
from .serializers import AssignmentWriteSerializer, InvitationWriteSerializer, JobRoleAssignmentSerializer, JobRoleSerializer

User = get_user_model()


def _workspace(request):
    raw = request.headers.get('X-Workspace-Id', '').strip()
    members = WorkspaceMember.objects.select_related('workspace', 'organization_member').filter(
        organization_member__user=request.user, organization_member__is_active=True, is_active=True,
    )
    return members.filter(workspace_id=raw).first() if raw.isdigit() else members.order_by('-workspace__is_default', 'workspace_id').first()


def _admin(membership):
    if not membership:
        return False
    if membership.role in {OrganizationMember.Role.OWNER, OrganizationMember.Role.ADMIN}:
        return True
    user = membership.organization_member.user
    email = getattr(getattr(user, 'google_account', None), 'email', '') or getattr(user, 'email', '')
    return email.strip().lower() in settings.RBAC_BOOTSTRAP_ADMIN_EMAILS


def _visible_members(membership):
    base = WorkspaceMember.objects.select_related('organization_member__user').filter(
        workspace=membership.workspace,
        organization_member__is_active=True,
    )
    if _admin(membership):
        return base
    base = base.filter(is_active=True)
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


class DefaultRoleBootstrapView(APIView):
    """Create a practical editable starter hierarchy without replacing roles."""

    @transaction.atomic
    def post(self, request):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        defaults = (
            ('Direktor', 1, JobRole.Visibility.ALL),
            ('Rahbar', 10, JobRole.Visibility.LOWER),
            ('Menejer', 20, JobRole.Visibility.LOWER),
            ('Xodim', 100, JobRole.Visibility.SELF),
        )
        roles = []
        for name, rank, visibility in defaults:
            role, _ = JobRole.objects.get_or_create(
                workspace=membership.workspace,
                name=name,
                defaults={'rank': rank, 'visibility': visibility},
            )
            roles.append(role)
        return Response(JobRoleSerializer(roles, many=True).data)


class MemberListView(APIView):
    def get(self, request):
        membership = _workspace(request)
        if not membership:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        members = _visible_members(membership).order_by('organization_member__user__first_name', 'id')
        assignments = {item.workspace_member_id: item for item in JobRoleAssignment.objects.select_related('role', 'workspace_member__organization_member__user', 'workspace_member__organization_member__user__google_account').filter(workspace_member__in=members)}
        payload = []
        for item in members:
            assignment = assignments.get(item.id)
            if assignment:
                payload.append(JobRoleAssignmentSerializer(assignment).data)
            else:
                user = item.organization_member.user
                payload.append({'member_id': item.id, 'user_id': user.id, 'display_name': user.first_name or user.username, 'email': getattr(getattr(user, 'google_account', None), 'email', '') or getattr(user, 'email', ''), 'system_role': item.role, 'is_active': item.is_active, 'role': None})
        return Response(payload)


class RegisteredUserListView(APIView):
    """Users who registered but have not yet been added to this organization."""

    def get(self, request):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        users = User.objects.exclude(
            organization_memberships__organization=membership.workspace.organization,
        ).order_by('-date_joined', '-id')[:200]
        return Response([
            {
                'user_id': user.id,
                'display_name': user.first_name or user.username,
                'email': getattr(getattr(user, 'google_account', None), 'email', '') or getattr(user, 'email', ''),
                'avatar_url': getattr(user, 'avatar_url', '') or '',
            }
            for user in users
        ])


class AddRegisteredUserView(APIView):
    @transaction.atomic
    def post(self, request):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        try:
            user = User.objects.get(id=request.data.get('user_id'))
        except (User.DoesNotExist, TypeError, ValueError):
            return Response({'detail': 'Registered user not found.'}, status=404)
        organization_member, _ = OrganizationMember.objects.get_or_create(
            organization=membership.workspace.organization,
            user=user,
            defaults={'role': OrganizationMember.Role.MEMBER},
        )
        workspace_member, _ = WorkspaceMember.objects.get_or_create(
            workspace=membership.workspace,
            organization_member=organization_member,
            defaults={'role': OrganizationMember.Role.MEMBER},
        )
        role_id = request.data.get('role_id')
        role = JobRole.objects.filter(id=role_id, workspace=membership.workspace, is_active=True).first() if role_id else None
        if role_id and not role:
            return Response({'detail': 'Role not found.'}, status=404)
        if role:
            JobRoleAssignment.objects.update_or_create(
                workspace_member=workspace_member,
                defaults={'role': role, 'assigned_by': request.user},
            )
        return Response({'member_id': workspace_member.id, 'user_id': user.id}, status=201)


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


class InvitationCreateView(APIView):
    @transaction.atomic
    def post(self, request):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        serializer = InvitationWriteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invitation = Invitation.objects.create(
            organization=membership.workspace.organization,
            workspace=membership.workspace,
            invited_by=request.user,
            email=serializer.validated_data['email'],
            role=OrganizationMember.Role.MEMBER,
            invite_code=uuid4().hex,
        )
        return Response({'id': invitation.id, 'email': invitation.email, 'invite_code': invitation.invite_code, 'status': invitation.status}, status=status.HTTP_201_CREATED)


class MemberDeactivateView(APIView):
    @transaction.atomic
    def post(self, request, member_id):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        target = WorkspaceMember.objects.filter(id=member_id, workspace=membership.workspace, is_active=True).first()
        if not target:
            return Response({'detail': 'Workspace member not found.'}, status=404)
        if target.id == membership.id:
            return Response({'detail': 'You cannot deactivate yourself.'}, status=400)
        target.is_active = False
        target.save(update_fields=['is_active', 'updated_at'])
        return Response(status=204)


class MemberReactivateView(APIView):
    @transaction.atomic
    def post(self, request, member_id):
        membership = _workspace(request)
        if not _admin(membership):
            return Response({'detail': 'Administrator rights required.'}, status=403)
        target = WorkspaceMember.objects.filter(
            id=member_id,
            workspace=membership.workspace,
        ).first()
        if not target:
            return Response({'detail': 'Workspace member not found.'}, status=404)
        target.is_active = True
        target.save(update_fields=['is_active', 'updated_at'])
        return Response(status=204)
