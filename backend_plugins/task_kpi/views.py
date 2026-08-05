from collections import defaultdict

from django.db import transaction
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import OrganizationMember, WorkspaceMember

from .models import KpiGoal, WorkTask
from .serializers import KpiGoalSerializer, WorkTaskSerializer


def _membership(request):
    raw = request.headers.get('X-Workspace-Id', '').strip()
    members = WorkspaceMember.objects.select_related('workspace').filter(
        organization_member__user=request.user,
        organization_member__is_active=True,
        is_active=True,
    )
    return members.filter(workspace_id=raw).first() if raw.isdigit() else members.order_by('-workspace__is_default', 'workspace_id').first()


def _manager(member):
    return bool(member and member.role in {OrganizationMember.Role.OWNER, OrganizationMember.Role.ADMIN})


def _assignable_members(member):
    base = WorkspaceMember.objects.select_related('organization_member__user').filter(
        workspace=member.workspace, is_active=True, organization_member__is_active=True,
    )
    if _manager(member):
        return base
    # RBAC stays optional: without it, non-admins cannot delegate work.
    try:
        from backend_plugins.rbac.models import JobRoleAssignment
    except Exception:
        return base.none()
    own = JobRoleAssignment.objects.select_related('role').filter(workspace_member=member).first()
    if not own or not own.role:
        return base.none()
    if own.role.visibility == 'all':
        return base.exclude(id=member.id)
    if own.role.visibility != 'lower':
        return base.none()
    lower_ids = JobRoleAssignment.objects.filter(
        role__workspace=member.workspace,
        role__rank__gt=own.role.rank,
        role__is_active=True,
    ).values_list('workspace_member_id', flat=True)
    return base.filter(id__in=lower_ids)


def _can_assign(member, assignee_id):
    return _assignable_members(member).filter(id=assignee_id).exists()


class TaskListCreateView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        tasks = WorkTask.objects.select_related('assignee__organization_member__user').filter(workspace=member.workspace)
        can_delegate = _assignable_members(member).exists()
        if not _manager(member) and not can_delegate:
            tasks = tasks.filter(assignee=member)
        elif not _manager(member):
            tasks = tasks.filter(Q(assignee=member) | Q(created_by=request.user))
        if status_filter := request.query_params.get('status'):
            tasks = tasks.filter(status=status_filter)
        return Response(WorkTaskSerializer(tasks, many=True, context={'workspace': member.workspace}).data)

    @transaction.atomic
    def post(self, request):
        member = _membership(request)
        assignee_id = request.data.get('assignee_id')
        if not assignee_id or not _can_assign(member, assignee_id):
            return Response({'detail': 'You can assign work only to lower-role employees.'}, status=403)
        serializer = WorkTaskSerializer(data=request.data, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        assignee_id = serializer.validated_data.pop('assignee_id')
        task = WorkTask.objects.create(
            workspace=member.workspace,
            created_by=request.user,
            assignee_id=assignee_id,
            **serializer.validated_data,
        )
        return Response(WorkTaskSerializer(task, context={'workspace': member.workspace}).data, status=status.HTTP_201_CREATED)


class TaskDetailView(APIView):
    def patch(self, request, task_id):
        member = _membership(request)
        task = WorkTask.objects.filter(id=task_id, workspace=member.workspace if member else None).first()
        if not member or not task:
            return Response({'detail': 'Task not found.'}, status=404)
        is_creator = task.created_by_id == request.user.id
        if not _manager(member) and task.assignee_id != member.id and not is_creator:
            return Response({'detail': 'Task access denied.'}, status=403)
        requested_status = request.data.get('status')
        if task.assignee_id == member.id and not is_creator:
            allowed = {'in_progress', 'submitted'}
            if requested_status not in allowed or set(request.data).difference({'status', 'completion_note'}):
                return Response({'detail': 'Assignee can start or submit only their assigned work.'}, status=403)
            if requested_status == 'submitted':
                task.submitted_at = timezone.now()
        elif is_creator or _manager(member):
            if requested_status == 'done':
                task.reviewed_at = timezone.now()
                task.completed_at = timezone.now()
            elif requested_status == 'returned':
                task.reviewed_at = timezone.now()
        serializer = WorkTaskSerializer(task, data=request.data, partial=True, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        return Response(WorkTaskSerializer(serializer.save(), context={'workspace': member.workspace}).data)


class AssignableMemberView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        rows = _assignable_members(member)
        return Response([
            {'member_id': item.id, 'name': item.organization_member.user.first_name or item.organization_member.user.username}
            for item in rows
        ])


class KpiSummaryView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        visible = _assignable_members(member)
        if not _manager(member):
            visible = visible | WorkspaceMember.objects.filter(id=member.id)
        totals = WorkTask.objects.filter(workspace=member.workspace, assignee__in=visible).values('assignee_id').annotate(total=Count('id'), done=Count('id', filter=Q(status='done')))
        stats = {row['assignee_id']: row for row in totals}
        return Response([{
            'member_id': item.id,
            'name': item.organization_member.user.first_name or item.organization_member.user.username,
            'total': stats.get(item.id, {}).get('total', 0),
            'done': stats.get(item.id, {}).get('done', 0),
        } for item in visible])


class KpiGoalListCreateView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        goals = KpiGoal.objects.select_related('owner__organization_member__user').filter(workspace=member.workspace)
        if not _manager(member):
            goals = goals.filter(owner=member)
        return Response(KpiGoalSerializer(goals, many=True, context={'workspace': member.workspace}).data)

    def post(self, request):
        member = _membership(request)
        if not _manager(member):
            return Response({'detail': 'Manager rights required.'}, status=403)
        serializer = KpiGoalSerializer(data=request.data, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        owner_id = serializer.validated_data.pop('owner_id')
        goal = KpiGoal.objects.create(workspace=member.workspace, owner_id=owner_id, **serializer.validated_data)
        return Response(KpiGoalSerializer(goal, context={'workspace': member.workspace}).data, status=status.HTTP_201_CREATED)
