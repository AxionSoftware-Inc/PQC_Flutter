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
    TaskNotification.objects.bulk_create([
        TaskNotification(
            task=task,
            activity=activity,
            recipient_id=member_id,
            kind=activity.kind,
        )
        for member_id in recipient_ids
    ])
