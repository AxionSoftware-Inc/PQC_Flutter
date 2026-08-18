from django.conf import settings
from django.db import models

from users.models import Workspace, WorkspaceMember


class WorkTask(models.Model):
    class Status(models.TextChoices):
        TODO = 'todo', 'Bajarilishi kerak'
        ACCEPTED = 'accepted', 'Qabul qilindi'
        IN_PROGRESS = 'in_progress', 'Jarayonda'
        SUBMITTED = 'submitted', 'Topshirildi'
        DONE = 'done', 'Qabul qilindi'
        RETURNED = 'returned', 'Qayta ishlashda'
        CANCELLED = 'cancelled', 'Bekor qilindi'

    class Priority(models.TextChoices):
        LOW = 'low', 'Past'
        NORMAL = 'normal', 'Oddiy'
        HIGH = 'high', 'Yuqori'
        URGENT = 'urgent', 'Shoshilinch'

    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name='work_tasks')
    title = models.CharField(max_length=240)
    description = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.TODO)
    priority = models.CharField(max_length=12, choices=Priority.choices, default=Priority.NORMAL)
    assignee = models.ForeignKey(WorkspaceMember, on_delete=models.SET_NULL, related_name='assigned_tasks', null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, related_name='created_work_tasks', null=True)
    due_at = models.DateTimeField(null=True, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    completion_note = models.TextField(blank=True)
    review_note = models.TextField(blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    cancelled_at = models.DateTimeField(null=True, blank=True)
    cancellation_note = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['status', '-updated_at', '-id']
        indexes = [models.Index(fields=['workspace', 'status']), models.Index(fields=['workspace', 'assignee'])]


class KpiGoal(models.Model):
    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name='kpi_goals')
    owner = models.ForeignKey(WorkspaceMember, on_delete=models.CASCADE, related_name='kpi_goals')
    title = models.CharField(max_length=180)
    unit = models.CharField(max_length=24, default='ta')
    target_value = models.DecimalField(max_digits=14, decimal_places=2)
    current_value = models.DecimalField(max_digits=14, decimal_places=2, default=0)
    period_start = models.DateField()
    period_end = models.DateField()
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['period_end', 'id']
        indexes = [models.Index(fields=['workspace', 'owner', 'is_active'])]


class KpiGoalHistory(models.Model):
    goal = models.ForeignKey(KpiGoal, on_delete=models.CASCADE, related_name='history')
    target_value = models.DecimalField(max_digits=14, decimal_places=2)
    current_value = models.DecimalField(max_digits=14, decimal_places=2)
    period_start = models.DateField()
    period_end = models.DateField()
    changed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']


class TaskAttachment(models.Model):
    task = models.ForeignKey(WorkTask, on_delete=models.CASCADE, related_name='attachments')
    activity = models.ForeignKey(
        'TaskActivity',
        on_delete=models.CASCADE,
        related_name='attachments',
        null=True,
        blank=True,
    )
    file = models.FileField(upload_to='task-kpi/%Y/%m/')
    filename = models.CharField(max_length=255)
    size_bytes = models.PositiveBigIntegerField()
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True)
    created_at = models.DateTimeField(auto_now_add=True)


class TaskWatcher(models.Model):
    """A read-and-comment participant who does not execute the task."""

    task = models.ForeignKey(WorkTask, on_delete=models.CASCADE, related_name='watchers')
    member = models.ForeignKey(WorkspaceMember, on_delete=models.CASCADE, related_name='watched_tasks')
    added_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['task', 'member'], name='task_kpi_unique_task_watcher')]


class TaskActivity(models.Model):
    class Kind(models.TextChoices):
        COMMENT = 'comment', 'Izoh'
        WORKFLOW = 'workflow', 'Jarayon'
        CHANGE = 'change', 'O\'zgarish'
        SYSTEM = 'system', 'Tizim'

    task = models.ForeignKey(WorkTask, on_delete=models.CASCADE, related_name='activities')
    kind = models.CharField(max_length=16, choices=Kind.choices, default=Kind.COMMENT)
    body = models.TextField(blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    is_pinned = models.BooleanField(default=False)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='task_activities')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at', 'id']
        indexes = [models.Index(fields=['task', 'created_at'])]


class TaskNotification(models.Model):
    """In-app notification inbox. Delivery services may consume this later."""

    task = models.ForeignKey(WorkTask, on_delete=models.CASCADE, related_name='notifications')
    activity = models.ForeignKey(TaskActivity, on_delete=models.CASCADE, related_name='notifications')
    recipient = models.ForeignKey(WorkspaceMember, on_delete=models.CASCADE, related_name='task_notifications')
    kind = models.CharField(max_length=24)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [models.Index(fields=['recipient', 'read_at', 'created_at'])]
