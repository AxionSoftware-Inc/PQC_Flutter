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
from users.serializers import avatar_url_for_user

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



from .common import _assignable_members, _membership

class TaskNotificationView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        notifications = TaskNotification.objects.filter(recipient=member).select_related('task', 'activity__created_by').prefetch_related('activity__attachments')[:100]
        unread = TaskNotification.objects.filter(recipient=member, read_at__isnull=True).count()
        return Response({'unread_count': unread, 'items': TaskNotificationSerializer(notifications, many=True).data})


class TaskNotificationReadView(APIView):
    @transaction.atomic
    def post(self, request, notification_id=None):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        rows = TaskNotification.objects.filter(recipient=member, read_at__isnull=True)
        if notification_id is not None:
            rows = rows.filter(id=notification_id)
        rows.update(read_at=timezone.now())
        return Response(status=204)


class AssignableMemberView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        rows = _assignable_members(member)
        try:
            from backend_plugins.rbac.models import JobRoleAssignment
            assignments = {item.workspace_member_id: item for item in JobRoleAssignment.objects.select_related('role').filter(workspace_member__in=rows)}
        except Exception:
            assignments = {}
        return Response([{
            'member_id': item.id,
            'name': item.organization_member.user.first_name or item.organization_member.user.username,
            'role_name': getattr(assignments.get(item.id), 'role', None).name if getattr(assignments.get(item.id), 'role', None) else 'Lavozim belgilanmagan',
            'avatar_url': avatar_url_for_user(
                item.organization_member.user,
                request,
            ),
        } for item in rows])


class TaskDashboardView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        tasks = _visible_tasks(member)
        now = timezone.now()
        active = tasks.exclude(status__in=['done', 'cancelled'])
        mine = active.filter(assignee=member)
        status_counts = {row['status']: row['count'] for row in tasks.values('status').annotate(count=Count('id'))}
        team = _assignable_members(member)
        team_totals = WorkTask.objects.filter(workspace=member.workspace, assignee__in=team).values('assignee_id').annotate(
            total=Count('id'),
            done=Count('id', filter=Q(status='done')),
            overdue=Count('id', filter=Q(due_at__lt=now) & ~Q(status__in=['done', 'cancelled'])),
        )
        totals = {row['assignee_id']: row for row in team_totals}
        return Response({
            'mine_open': mine.count(),
            'assigned_by_me_open': active.filter(created_by=request.user).count(),
            'overdue': active.filter(due_at__lt=now).count(),
            'due_today': active.filter(due_at__date=now.date()).count(),
            'status_counts': status_counts,
            'team': [{
                'member_id': item.id,
                'name': item.organization_member.user.first_name or item.organization_member.user.username,
                **totals.get(item.id, {'total': 0, 'done': 0, 'overdue': 0}),
            } for item in team],
        })


class TaskReportView(APIView):
    """Compact operational report; CSV is deliberately generated server-side."""

    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        tasks = _visible_tasks(member)
        for key, lookup in (('from', 'created_at__date__gte'), ('to', 'created_at__date__lte')):
            value = request.query_params.get(key)
            if value:
                try:
                    tasks = tasks.filter(**{lookup: datetime.fromisoformat(value).date()})
                except ValueError:
                    return Response({'detail': f'Invalid {key} date.'}, status=400)
        rows = list(tasks)
        now = timezone.now()
        completed_durations = [
            (task.completed_at - task.started_at).total_seconds()
            for task in rows
            if task.completed_at and task.started_at
        ]
        payload = {
            'total': len(rows),
            'done': sum(task.status == 'done' for task in rows),
            'returned': sum(task.status == 'returned' for task in rows),
            'overdue': sum(
                1
                for task in rows
                if task.due_at
                and task.due_at < now
                and task.status not in {'done', 'cancelled'}
            ),
            'average_completion_hours': round(sum(completed_durations) / len(completed_durations) / 3600, 1) if completed_durations else 0,
        }
        if request.query_params.get('format') != 'csv':
            return Response(payload)
        response = HttpResponse(content_type='text/csv; charset=utf-8')
        response['Content-Disposition'] = 'attachment; filename="task-report.csv"'
        writer = csv.writer(response)
        writer.writerow(['total', 'done', 'returned', 'overdue', 'average_completion_hours'])
        writer.writerow([payload[key] for key in ('total', 'done', 'returned', 'overdue', 'average_completion_hours')])
        return response


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
