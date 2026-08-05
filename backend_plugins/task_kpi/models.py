from django.conf import settings
from django.db import models

from users.models import Workspace, WorkspaceMember


class WorkTask(models.Model):
    class Status(models.TextChoices):
        TODO = 'todo', 'Bajarilishi kerak'
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
    completed_at = models.DateTimeField(null=True, blank=True)
    completion_note = models.TextField(blank=True)
    review_note = models.TextField(blank=True)
    submitted_at = models.DateTimeField(null=True, blank=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
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
