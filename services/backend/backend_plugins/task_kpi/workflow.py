"""Task workflow policy owned by the Task/KPI plugin.

The client receives actions, not inferred permissions.  This keeps the UI
honest while the server remains the authority for every state transition.
"""

from .models import WorkTask


_ASSIGNEE_ACTIONS = {
    WorkTask.Status.TODO: ('accept',),
    WorkTask.Status.ACCEPTED: ('start',),
    WorkTask.Status.RETURNED: ('resume',),
    WorkTask.Status.IN_PROGRESS: ('submit',),
}

_REVIEW_ACTIONS = {
    WorkTask.Status.SUBMITTED: ('approve', 'return'),
}

ACTION_STATUS = {
    'accept': WorkTask.Status.ACCEPTED,
    'start': WorkTask.Status.IN_PROGRESS,
    'resume': WorkTask.Status.IN_PROGRESS,
    'submit': WorkTask.Status.SUBMITTED,
    'approve': WorkTask.Status.DONE,
    'return': WorkTask.Status.RETURNED,
}


def available_actions(task, member, *, can_manage: bool) -> tuple[str, ...]:
    """Return the actions this workspace member may take on this task.

    An assignee executes work even when they are also a manager.  A manager or
    creator reviews a different person's submitted work.  This ordering avoids
    the old role collision where a manager-assignee was treated as reviewer.
    """
    if task.assignee_id == member.id:
        return _ASSIGNEE_ACTIONS.get(task.status, ())
    if can_manage:
        return _REVIEW_ACTIONS.get(task.status, ())
    return ()
