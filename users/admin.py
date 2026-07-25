from django.contrib import admin

from users.models import (
    WorkspaceAccessRole,
    WorkspaceAccessRoleAssignment,
    WorkspaceAccessRolePermission,
)


class WorkspaceAccessRolePermissionInline(admin.TabularInline):
    model = WorkspaceAccessRolePermission
    extra = 0


@admin.register(WorkspaceAccessRole)
class WorkspaceAccessRoleAdmin(admin.ModelAdmin):
    list_display = ('name', 'key', 'workspace', 'is_active', 'updated_at')
    list_filter = ('is_active', 'workspace__organization')
    search_fields = ('name', 'key', 'workspace__name')
    inlines = (WorkspaceAccessRolePermissionInline,)


@admin.register(WorkspaceAccessRoleAssignment)
class WorkspaceAccessRoleAssignmentAdmin(admin.ModelAdmin):
    list_display = ('workspace_member', 'role', 'assigned_by', 'created_at')
    list_filter = ('role__workspace', 'role')
    search_fields = (
        'workspace_member__organization_member__user__username',
        'role__name',
    )
