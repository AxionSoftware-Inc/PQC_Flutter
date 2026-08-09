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

from .activity import record_activity
from .models import KpiGoal, KpiGoalHistory, TaskActivity, TaskAttachment, TaskNotification, TaskWatcher, WorkTask
from .permissions import can_comment_on_task, can_manage_task, can_view_task
from .serializers import (
    KpiGoalSerializer,
    KpiGoalHistorySerializer,
    TaskActivitySerializer,
    TaskAttachmentSerializer,
    TaskNotificationSerializer,
    WorkTaskSerializer,
)
from .workflow import ACTION_STATUS, available_actions


def _membership(request):
    raw = request.headers.get('X-Workspace-Id', '').strip()
    members = WorkspaceMember.objects.select_related('workspace', 'organization_member__user').filter(
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


def _task_serializer_context(member):
    return {
        'workspace': member.workspace,
        'actor_member': member,
        'assignable_members': _assignable_members(member),
    }


def _visible_tasks(member):
    assignable = _assignable_members(member)
    return WorkTask.objects.select_related('assignee__organization_member__user').prefetch_related(
        'watchers', 'attachments',
    ).filter(workspace=member.workspace).filter(
        Q(assignee=member)
        | Q(created_by=member.organization_member.user)
        | Q(watchers__member=member)
        | Q(assignee__in=assignable)
    ).distinct()


def _get_task(member, task_id, *, for_update=False):
    # ``_visible_tasks`` joins watchers/assignees and therefore uses DISTINCT.
    # PostgreSQL rejects ``SELECT DISTINCT ... FOR UPDATE``. Resolve the row
    # from its workspace first, then apply the visibility policy in Python.
    # A nullable assignee join is also not lockable in PostgreSQL, so the
    # locking query must contain only the WorkTask table. Related objects are
    # loaded normally for non-mutating reads.
    tasks = WorkTask.objects.filter(workspace=member.workspace, id=task_id)
    if for_update:
        tasks = tasks.select_for_update()
    else:
        tasks = tasks.select_related(
            'assignee__organization_member__user',
        ).prefetch_related('watchers', 'attachments')
    task = tasks.first()
    if not task or not can_view_task(task, member, _assignable_members(member)):
        return None
    return task


class TaskListCreateView(APIView):
    def get(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        tasks = _visible_tasks(member)
        scope = request.query_params.get('scope')
        if scope == 'mine':
            tasks = tasks.filter(assignee=member)
        elif scope == 'assigned':
            tasks = tasks.filter(created_by=request.user)
        elif scope == 'overdue':
            tasks = tasks.filter(due_at__lt=timezone.now()).exclude(status__in=['done', 'cancelled'])
        if status_filter := request.query_params.get('status'):
            if status_filter == 'open':
                # The inbox omits completed work by default; clients can
                # still request status=done explicitly when they need the
                # completed history.
                tasks = tasks.exclude(status=WorkTask.Status.DONE)
            else:
                tasks = tasks.filter(status=status_filter)
        if priority := request.query_params.get('priority'):
            tasks = tasks.filter(priority=priority)
        if query := request.query_params.get('q', '').strip():
            tasks = tasks.filter(Q(title__icontains=query) | Q(description__icontains=query))
        tasks = tasks.order_by('-updated_at', '-id')
        # Keep the original list response for old clients. New clients can
        # opt into a bounded page without breaking deployed builds.
        paginated = 'limit' in request.query_params or 'offset' in request.query_params
        if not paginated:
            return Response(WorkTaskSerializer(tasks, many=True, context=_task_serializer_context(member)).data)
        try:
            offset = max(int(request.query_params.get('offset', '0')), 0)
            limit = min(max(int(request.query_params.get('limit', '50')), 1), 100)
        except ValueError:
            return Response({'detail': 'Invalid pagination parameters.'}, status=400)
        page = list(tasks[offset:offset + limit + 1])
        has_more = len(page) > limit
        page = page[:limit]
        return Response({
            'items': WorkTaskSerializer(page, many=True, context=_task_serializer_context(member)).data,
            'next_offset': offset + limit if has_more else None,
            'has_more': has_more,
        })

    @transaction.atomic
    def post(self, request):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        data = request.data.copy()
        watcher_ids = data.pop('watcher_ids', [])
        assignee_id = data.get('assignee_id')
        if not assignee_id or not _can_assign(member, assignee_id):
            return Response({'detail': 'You can assign work only to employees in your reporting scope.'}, status=403)
        allowed_fields = {'title', 'description', 'priority', 'assignee_id', 'due_at'}
        if set(data).difference(allowed_fields):
            return Response({'detail': 'New tasks always start in the todo state.'}, status=400)
        serializer = WorkTaskSerializer(data=data, context=_task_serializer_context(member))
        serializer.is_valid(raise_exception=True)
        assignee_id = serializer.validated_data.pop('assignee_id')
        task = WorkTask.objects.create(
            workspace=member.workspace,
            created_by=request.user,
            assignee_id=assignee_id,
            **serializer.validated_data,
        )
        error = _replace_watchers(task, member, watcher_ids, request.user)
        if error:
            return Response({'detail': error}, status=400)
        record_activity(
            task,
            kind=TaskActivity.Kind.WORKFLOW,
            body='Vazifa yaratildi.',
            actor=request.user,
            metadata={'event': 'created', 'assignee_id': task.assignee_id},
        )
        return Response(WorkTaskSerializer(task, context=_task_serializer_context(member)).data, status=status.HTTP_201_CREATED)


class TaskDetailView(APIView):
    """Only workflow transitions live here; field edits have their own endpoint."""

    @transaction.atomic
    def patch(self, request, task_id):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Task not found.'}, status=404)
        task = _get_task(member, task_id, for_update=True)
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)
        actions = available_actions(
            task,
            member,
            can_manage=can_manage_task(task, member, _assignable_members(member)),
        )
        requested_status = request.data.get('status')
        requested_action = next((action for action in actions if ACTION_STATUS[action] == requested_status), None)
        if not requested_action:
            return Response({'detail': 'Invalid task status transition.'}, status=409)

        allowed_fields = {'status'}
        if requested_action == 'submit':
            allowed_fields.add('completion_note')
        elif requested_action == 'return':
            allowed_fields.add('review_note')
            if not str(request.data.get('review_note', '')).strip():
                return Response({'detail': 'A review note is required when returning work.'}, status=400)
        if set(request.data).difference(allowed_fields):
            return Response({'detail': 'This action cannot modify task details.'}, status=403)

        now = timezone.now()
        if requested_action in {'start', 'resume'} and not task.started_at:
            task.started_at = now
        if requested_action == 'submit':
            task.submitted_at = now
        elif requested_action in {'approve', 'return'}:
            task.reviewed_at = now
        if requested_action == 'approve':
            task.completed_at = now
        serializer = WorkTaskSerializer(task, data=request.data, partial=True, context=_task_serializer_context(member))
        serializer.is_valid(raise_exception=True)
        task = serializer.save()
        action_text = {
            'accept': 'Vazifa qabul qilindi.',
            'start': 'Ish boshlandi.',
            'resume': 'Qayta ishlash boshlandi.',
            'submit': 'Ish rahbarga topshirildi.',
            'approve': 'Ish qabul qilindi.',
            'return': 'Ish qayta ishlashga qaytarildi.',
        }[requested_action]
        record_activity(
            task,
            kind=TaskActivity.Kind.WORKFLOW,
            body=action_text,
            actor=request.user,
            metadata={'event': requested_action, 'status': task.status},
        )
        return Response(WorkTaskSerializer(task, context=_task_serializer_context(member)).data)


class TaskManageView(APIView):
    """Manager-only lifecycle fields: reassignment, deadline, priority, watchers and cancellation."""

    @transaction.atomic
    def patch(self, request, task_id):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Task not found.'}, status=404)
        task = _get_task(member, task_id, for_update=True)
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)
        if not can_manage_task(task, member, _assignable_members(member)):
            return Response({'detail': 'Task management rights required.'}, status=403)

        data = request.data.copy()
        allowed = {'due_at', 'priority', 'assignee_id', 'watcher_ids', 'cancellation_note'}
        if not data or set(data).difference(allowed):
            return Response({'detail': 'Unsupported task management update.'}, status=400)
        if 'cancellation_note' in data:
            if len(data) != 1:
                return Response({'detail': 'Cancellation must be a separate action.'}, status=400)
            if task.status in {WorkTask.Status.DONE, WorkTask.Status.CANCELLED}:
                return Response({'detail': 'This task can no longer be cancelled.'}, status=409)
            note = str(data['cancellation_note']).strip()
            if not note:
                return Response({'detail': 'Cancellation reason is required.'}, status=400)
            task.status = WorkTask.Status.CANCELLED
            task.cancelled_at = timezone.now()
            task.cancellation_note = note
            task.save(update_fields=['status', 'cancelled_at', 'cancellation_note', 'updated_at'])
            record_activity(task, kind=TaskActivity.Kind.WORKFLOW, body='Vazifa bekor qilindi.', actor=request.user, metadata={'event': 'cancelled', 'reason': note})
            return Response(WorkTaskSerializer(task, context=_task_serializer_context(member)).data)
        if task.status == WorkTask.Status.CANCELLED:
            return Response({'detail': 'Cancelled tasks cannot be changed.'}, status=409)

        changes = []
        if 'assignee_id' in data:
            assignee_id = data['assignee_id']
            if not _can_assign(member, assignee_id):
                return Response({'detail': 'New assignee is outside your reporting scope.'}, status=403)
            if task.assignee_id != assignee_id:
                task.assignee_id = assignee_id
                task.status = WorkTask.Status.TODO
                task.started_at = task.submitted_at = task.reviewed_at = task.completed_at = None
                task.completion_note = task.review_note = ''
                changes.append('Bajaruvchi almashtirildi va vazifa qayta ochildi.')
        if 'priority' in data:
            if data['priority'] not in WorkTask.Priority.values:
                return Response({'detail': 'Invalid priority.'}, status=400)
            if task.priority != data['priority']:
                task.priority = data['priority']
                changes.append('Ustuvorlik yangilandi.')
        if 'due_at' in data:
            due_at = data['due_at']
            if due_at in (None, ''):
                task.due_at = None
            else:
                field = WorkTask._meta.get_field('due_at')
                try:
                    task.due_at = field.to_python(due_at)
                except (TypeError, ValueError):
                    return Response({'detail': 'Invalid deadline.'}, status=400)
            changes.append('Muddat yangilandi.')
        if 'watcher_ids' in data:
            error = _replace_watchers(task, member, data['watcher_ids'], request.user)
            if error:
                return Response({'detail': error}, status=400)
            changes.append('Kuzatuvchilar yangilandi.')
        if not changes:
            return Response(WorkTaskSerializer(task, context=_task_serializer_context(member)).data)
        task.save()
        record_activity(task, kind=TaskActivity.Kind.CHANGE, body=' '.join(changes), actor=request.user, metadata={'event': 'managed', 'changes': changes})
        return Response(WorkTaskSerializer(task, context=_task_serializer_context(member)).data)


class TaskActivityView(APIView):
    def get(self, request, task_id):
        member = _membership(request)
        task = _get_task(member, task_id) if member else None
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)
        activities = TaskActivity.objects.filter(task=task).select_related('created_by').prefetch_related('attachments')
        return Response(TaskActivitySerializer(activities, many=True).data)

    @transaction.atomic
    def post(self, request, task_id):
        member = _membership(request)
        task = _get_task(member, task_id, for_update=True) if member else None
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)
        if not can_comment_on_task(task, member, _assignable_members(member)):
            return Response({'detail': 'Comment access denied.'}, status=403)
        body = str(request.data.get('body', '')).strip()
        if not body:
            return Response({'detail': 'Message text is required.'}, status=400)
        if len(body) > 4000:
            return Response({'detail': 'Message must not exceed 4000 characters.'}, status=400)
        activity = record_activity(task, kind=TaskActivity.Kind.COMMENT, body=body, actor=request.user)
        return Response(TaskActivitySerializer(activity).data, status=status.HTTP_201_CREATED)


class TaskAttachmentCreateView(APIView):
    @transaction.atomic
    def post(self, request, task_id):
        member = _membership(request)
        task = _get_task(member, task_id, for_update=True) if member else None
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)
        if not can_comment_on_task(task, member, _assignable_members(member)):
            return Response({'detail': 'Task attachment access denied.'}, status=403)
        file = request.FILES.get('file')
        if not file:
            return Response({'detail': 'file is required.'}, status=400)
        if file.size > 25 * 1024 * 1024:
            return Response({'detail': 'Task attachment must not exceed 25 MB.'}, status=400)
        activity = record_activity(task, kind=TaskActivity.Kind.COMMENT, body=f'Fayl biriktirdi: {file.name}', actor=request.user)
        attachment = TaskAttachment.objects.create(task=task, activity=activity, file=file, filename=file.name, size_bytes=file.size, uploaded_by=request.user)
        return Response(TaskAttachmentSerializer(attachment).data, status=status.HTTP_201_CREATED)


class TaskAttachmentDownloadView(APIView):
    def get(self, request, attachment_id):
        member = _membership(request)
        attachment = TaskAttachment.objects.select_related('task').filter(id=attachment_id).first()
        if not member or not attachment or attachment.task.workspace_id != member.workspace_id:
            return Response({'detail': 'Attachment not found.'}, status=404)
        if not can_view_task(attachment.task, member, _assignable_members(member)):
            return Response({'detail': 'Attachment access denied.'}, status=403)
        return FileResponse(
            attachment.file.open('rb'),
            as_attachment=True,
            filename=attachment.filename,
        )


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
            'avatar_url': getattr(item.organization_member.user, 'avatar_url', '') or '',
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


def _replace_watchers(task, member, watcher_ids, actor):
    if watcher_ids in (None, ''):
        watcher_ids = []
    if not isinstance(watcher_ids, list) or not all(isinstance(item, int) for item in watcher_ids):
        return 'watcher_ids must be a list of workspace member IDs.'
    candidates = WorkspaceMember.objects.filter(
        workspace=member.workspace,
        is_active=True,
        organization_member__is_active=True,
        id__in=set(watcher_ids),
    )
    if candidates.count() != len(set(watcher_ids)):
        return 'One or more watchers are not active workspace members.'
    # A watcher must be inside the assigning manager's reporting scope (or be
    # the manager themselves); this prevents upward information disclosure.
    allowed_ids = set(_assignable_members(member).values_list('id', flat=True)) | {member.id}
    if not set(watcher_ids).issubset(allowed_ids):
        return 'A watcher is outside your reporting scope.'
    TaskWatcher.objects.filter(task=task).delete()
    TaskWatcher.objects.bulk_create([
        TaskWatcher(task=task, member_id=watcher_id, added_by=actor)
        for watcher_id in set(watcher_ids)
        if watcher_id != task.assignee_id
    ])
    return None
