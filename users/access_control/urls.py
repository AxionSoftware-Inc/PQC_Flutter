from django.urls import path

from users.access_control.views import (
    AccessRoleAssignmentDetailView,
    AccessRoleAssignmentListCreateView,
    AccessRoleDetailView,
    AccessRoleListCreateView,
    MyAccessSnapshotView,
    PermissionCatalogView,
)


urlpatterns = [
    path('catalog', PermissionCatalogView.as_view(), name='rbac-catalog'),
    path('roles', AccessRoleListCreateView.as_view(), name='rbac-roles'),
    path(
        'roles/<int:role_id>',
        AccessRoleDetailView.as_view(),
        name='rbac-role-detail',
    ),
    path(
        'assignments',
        AccessRoleAssignmentListCreateView.as_view(),
        name='rbac-assignments',
    ),
    path(
        'assignments/<int:assignment_id>',
        AccessRoleAssignmentDetailView.as_view(),
        name='rbac-assignment-detail',
    ),
    path('me', MyAccessSnapshotView.as_view(), name='rbac-me'),
]
