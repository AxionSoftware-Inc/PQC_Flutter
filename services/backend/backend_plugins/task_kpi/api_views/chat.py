from django.db import transaction
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation
from chat.serializers import ConversationSerializer

from ..models import TaskWatcher
from .common import _get_task, _membership


class TaskConversationView(APIView):
    """Return the durable app-chat conversation dedicated to one task."""

    @transaction.atomic
    def post(self, request, task_id):
        member = _membership(request)
        if not member:
            return Response({'detail': 'Active workspace not found.'}, status=403)
        task = _get_task(member, task_id)
        if not task:
            return Response({'detail': 'Task not found.'}, status=404)

        participant_ids = {request.user.id}
        if task.created_by_id:
            participant_ids.add(task.created_by_id)
        if task.assignee_id and task.assignee:
            participant_ids.add(task.assignee.organization_member.user_id)
        participant_ids.update(
            TaskWatcher.objects.filter(task=task).values_list(
                'member__organization_member__user_id',
                flat=True,
            )
        )

        conversation, _ = Conversation.objects.get_or_create(
            workspace=member.workspace,
            module=Conversation.Module.KPI,
            module_key=f'task:{task.id}',
            defaults={
                'type': Conversation.ConversationType.GROUP,
                'title': f'KPI • {task.title}',
            },
        )
        if conversation.type != Conversation.ConversationType.GROUP:
            return Response(
                {'detail': 'KPI conversation has an invalid type.'},
                status=409,
            )
        conversation.participants.set(sorted(participant_ids))
        return Response(
            ConversationSerializer(
                conversation,
                context={'request': request},
            ).data,
        )
