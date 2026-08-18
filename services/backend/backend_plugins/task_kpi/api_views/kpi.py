import csv
from datetime import datetime

from django.db import transaction
from django.db.models import Count, Q
from django.http import FileResponse, HttpResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from users.models import OrganizationMember, WorkspaceMember

from ..activity import record_activity
from ..models import KpiGoal, KpiGoalHistory, TaskActivity, TaskAttachment, TaskNotification, TaskWatcher, WorkTask
from ..permissions import can_comment_on_task, can_manage_task, can_view_task
from ..serializers import (
    KpiGoalSerializer,
    KpiGoalHistorySerializer,
    TaskActivitySerializer,
    TaskAttachmentSerializer,
    TaskNotificationSerializer,
    WorkTaskSerializer,
)
from ..workflow import ACTION_STATUS, available_actions



from .common import _assignable_members, _manager, _membership


class KpiSummaryView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        visible = _assignable_members(member) | WorkspaceMember.objects.filter(id=member.id)
        totals = WorkTask.objects.filter(workspace=member.workspace, assignee__in=visible).values('assignee_id').annotate(total=Count('id'), done=Count('id', filter=Q(status='done')))
        stats = {row['assignee_id']: row for row in totals}
        return Response([{
            'member_id': item.id,
            'name': item.organization_member.user.first_name or item.organization_member.user.username,
            'total': stats.get(item.id, {}).get('total', 0),
            'done': stats.get(item.id, {}).get('done', 0),
        } for item in visible.distinct()])

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


class KpiGoalDetailView(APIView):
    def get(self, request, goal_id):
        member = _membership(request)
        goal = KpiGoal.objects.filter(id=goal_id, workspace=member.workspace if member else None).first()
        if not member or not goal or (not _manager(member) and goal.owner_id != member.id):
            return Response({'detail': 'KPI goal not found.'}, status=404)
        return Response({
            'goal': KpiGoalSerializer(goal, context={'workspace': member.workspace}).data,
            'history': KpiGoalHistorySerializer(goal.history.all(), many=True).data,
        })

    @transaction.atomic
    def patch(self, request, goal_id):
        member = _membership(request)
        if not _manager(member):
            return Response({'detail': 'Manager rights required.'}, status=403)
        goal = KpiGoal.objects.filter(id=goal_id, workspace=member.workspace).first()
        if not goal:
            return Response({'detail': 'KPI goal not found.'}, status=404)
        allowed = {'title', 'unit', 'target_value', 'current_value', 'period_start', 'period_end', 'is_active'}
        if not request.data or set(request.data).difference(allowed):
            return Response({'detail': 'Unsupported KPI update.'}, status=400)
        before = (goal.target_value, goal.current_value, goal.period_start, goal.period_end)
        serializer = KpiGoalSerializer(goal, data=request.data, partial=True, context={'workspace': member.workspace})
        serializer.is_valid(raise_exception=True)
        goal = serializer.save()
        after = (goal.target_value, goal.current_value, goal.period_start, goal.period_end)
        if before != after:
            KpiGoalHistory.objects.create(
                goal=goal,
                target_value=before[0],
                current_value=before[1],
                period_start=before[2],
                period_end=before[3],
                changed_by=request.user,
            )
        return Response(KpiGoalSerializer(goal, context={'workspace': member.workspace}).data)
