from django.conf import settings
from django.db import models

from users.models import Workspace, WorkspaceMember


class JobRole(models.Model):
    class Visibility(models.TextChoices):
        ALL = 'all', 'Everyone'
        LOWER = 'lower', 'Only this role and lower roles'
        SELF = 'self', 'Only self'

    workspace = models.ForeignKey(Workspace, on_delete=models.CASCADE, related_name='job_roles')
    name = models.CharField(max_length=96)
    rank = models.PositiveIntegerField(help_text='1 is the highest position.')
    visibility = models.CharField(max_length=12, choices=Visibility.choices, default=Visibility.LOWER)
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['rank', 'name', 'id']
        constraints = [models.UniqueConstraint(fields=['workspace', 'name'], name='rbac_unique_role_name')]


class JobRoleAssignment(models.Model):
    workspace_member = models.OneToOneField(WorkspaceMember, on_delete=models.CASCADE, related_name='job_role_assignment')
    role = models.ForeignKey(JobRole, on_delete=models.SET_NULL, null=True, blank=True, related_name='assignments')
    assigned_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    updated_at = models.DateTimeField(auto_now=True)
