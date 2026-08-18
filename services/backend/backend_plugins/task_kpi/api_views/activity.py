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
)

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
        raw_metadata = request.data.get('metadata', {})
        if raw_metadata is None:
            raw_metadata = {}
        if not isinstance(raw_metadata, dict):
            return Response({'detail': 'metadata must be an object.'}, status=400)
        metadata = {}
        attachment_id = raw_metadata.get('reply_to_attachment_id')
        activity_id = raw_metadata.get('reply_to_activity_id')
        if attachment_id is not None and activity_id is not None:
            return Response({'detail': 'Only one reply target is allowed.'}, status=400)
        if attachment_id is not None:
            try:
                attachment_id = int(attachment_id)
            except (TypeError, ValueError):
                return Response({'detail': 'Invalid attachment reference.'}, status=400)
            attachment = TaskAttachment.objects.filter(task=task, id=attachment_id).first()
            if not attachment:
                return Response({'detail': 'Referenced attachment was not found.'}, status=400)
            metadata = {
                'reply_to_attachment_id': attachment.id,
                'reply_to_filename': attachment.filename,
            }
        elif activity_id is not None:
            try:
                activity_id = int(activity_id)
            except (TypeError, ValueError):
                return Response({'detail': 'Invalid comment reference.'}, status=400)
            referenced = TaskActivity.objects.filter(task=task, id=activity_id).first()
            if not referenced:
                return Response({'detail': 'Referenced comment was not found.'}, status=400)
            metadata = {
                'reply_to_activity_id': referenced.id,
                'reply_to_text': referenced.body[:240],
            }
        activity = record_activity(
            task,
            kind=TaskActivity.Kind.COMMENT,
            body=body,
            actor=request.user,
            metadata=metadata,
        )
        return Response(TaskActivitySerializer(activity).data, status=status.HTTP_201_CREATED)


class TaskActivityPinView(APIView):
    @transaction.atomic
    def post(self, request, task_id, activity_id):
        member = _membership(request)
        task = _get_task(member, task_id, for_update=True) if member else None
        if not task or not can_comment_on_task(task, member, _assignable_members(member)):
            return Response({'detail': 'Task not found.'}, status=404)
        activity = TaskActivity.objects.filter(task=task, id=activity_id).first()
        if not activity:
            return Response({'detail': 'Activity not found.'}, status=404)
        requested = request.data.get('pinned')
        pinned = bool(requested) if requested is not None else not activity.is_pinned
        if pinned:
            TaskActivity.objects.filter(task=task, is_pinned=True).exclude(id=activity.id).update(is_pinned=False)
        activity.is_pinned = pinned
        activity.save(update_fields=['is_pinned'])
        return Response(TaskActivitySerializer(activity).data)


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

