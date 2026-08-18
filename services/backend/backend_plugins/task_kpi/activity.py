"""Activity and notification services for the isolated Task/KPI plugin."""

from django.db import transaction

from .models import TaskActivity, TaskNotification


@transaction.atomic
def record_activity(task, *, kind, body='', actor=None, metadata=None, notify=True):
    activity = TaskActivity.objects.create(
        task=task,
        kind=kind,
        body=body.strip(),
        metadata=metadata or {},
        created_by=actor,
    )
    if notify:
        _notify_participants(task, activity, actor)
    return activity


def _notify_participants(task, activity, actor):
    recipient_ids = {member_id for member_id in (task.assignee_id,) if member_id}
    if task.created_by_id:
        recipient_ids.update(
            task.workspace.members.filter(
                organization_member__user_id=task.created_by_id,
                is_active=True,
            ).values_list('id', flat=True)[:1]
        )
    recipient_ids.update(task.watchers.values_list('member_id', flat=True))
    if actor:
        recipient_ids.discard(
            task.workspace.members.filter(
                organization_member__user_id=actor.id,
            ).values_list('id', flat=True).first()
        )
    notifications = TaskNotification.objects.bulk_create([
        TaskNotification(
            task=task,
            activity=activity,
            recipient_id=member_id,
            kind=activity.kind,
        )
        for member_id in recipient_ids
    ])
    # Broadcast a lightweight event to connected devices. The payload carries
    # no task secret; clients only use it to render a native notification and
    # then fetch the authoritative task inbox over the authenticated API.
    recipient_users = dict(
        task.workspace.members.filter(id__in=recipient_ids).values_list(
            'id', 'organization_member__user_id'
        )
    )
    actor_name = 'Rahbar'
    if actor is not None:
        actor_name = actor.first_name or actor.username
    for notification in notifications:
        recipient_user_id = recipient_users.get(notification.recipient_id)
        if not recipient_user_id:
            continue
        payload = {
            'notification_id': notification.id,
            'activity_id': activity.id,
            'task_id': task.id,
            'task_title': task.title,
            'kind': activity.kind,
            'sender_name': actor_name,
            'recipient_user_id': recipient_user_id,
        }
        transaction.on_commit(
            lambda payload=payload: _publish_task_notification(
                task.workspace_id, payload
            )
        )


def _publish_task_notification(workspace_id, payload):
    from asgiref.sync import async_to_sync
    from channels.layers import get_channel_layer

    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f'workspace_{workspace_id}',
        {
            'type': 'chat.event',
            'event': 'task.notification.created',
            'payload': payload,
        },
    )
