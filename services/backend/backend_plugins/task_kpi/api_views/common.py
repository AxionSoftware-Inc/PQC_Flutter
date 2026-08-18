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
