"""Authorization policy for Task/KPI.  Views never infer access from UI data."""


def can_manage_task(task, member, assignable_members):
    if task.created_by_id == member.organization_member.user_id:
        return True
    return assignable_members.filter(id=task.assignee_id).exists()


def can_view_task(task, member, assignable_members):
    return (
        task.assignee_id == member.id
        or task.created_by_id == member.organization_member.user_id
        or task.watchers.filter(member_id=member.id).exists()
        or can_manage_task(task, member, assignable_members)
    )


def can_comment_on_task(task, member, assignable_members):
    return task.status != 'cancelled' and can_view_task(task, member, assignable_members)
