from django.db import transaction
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


class TaskListCreateView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        tasks = WorkTask.objects.select_related('assignee__organization_member__user').filter(workspace=member.workspace)
        if not _manager(member):
            tasks = tasks.filter(assignee=member)
        if status_filter := request.query_params.get('status'):
            tasks = tasks.filter(status=status_filter)
        return Response(WorkTaskSerializer(tasks, many=True, context={'workspace': member.workspace}).data)

    @transaction.atomic
    def post(self, request):
        member = _membership(request)
        if not _manager(member):
            return Response({'detail': 'Manager rights required.'}, status=403)
        serializer = WorkTaskSerializer(data=request.data, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        assignee_id = serializer.validated_data.pop('assignee_id', None)
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
        if not _manager(member) and task.assignee_id != member.id:
            return Response({'detail': 'Task access denied.'}, status=403)
        restricted = {'title', 'description', 'priority', 'assignee_id', 'due_at'}
        if not _manager(member) and restricted.intersection(request.data):
            return Response({'detail': 'Only status can be updated.'}, status=403)
        serializer = WorkTaskSerializer(task, data=request.data, partial=True, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        return Response(WorkTaskSerializer(serializer.save(), context={'workspace': member.workspace}).data)


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
