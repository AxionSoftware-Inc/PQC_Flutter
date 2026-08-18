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



from .common import (
    _assignable_members,
    _can_assign,
    _get_task,
    _manager,
    _membership,
    _replace_watchers,
    _task_serializer_context,
    _visible_tasks,
)

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
