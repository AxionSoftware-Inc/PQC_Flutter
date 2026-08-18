from django.urls import path

from .views import (
    AssignableMemberView,
    KpiGoalListCreateView,
    KpiGoalDetailView,
    KpiSummaryView,
    TaskActivityView,
    TaskActivityPinView,
    TaskAttachmentDownloadView,
    TaskAttachmentCreateView,
    TaskDashboardView,
    TaskDetailView,
    TaskListCreateView,
    TaskManageView,
    TaskNotificationReadView,
    TaskNotificationView,
    TaskReportView,
)

urlpatterns = [
    path('tasks', TaskListCreateView.as_view()),
    path('tasks/<int:task_id>', TaskDetailView.as_view()),
    path('tasks/<int:task_id>/manage', TaskManageView.as_view()),
    path('tasks/<int:task_id>/activity', TaskActivityView.as_view()),
    path('tasks/<int:task_id>/activity/<int:activity_id>/pin', TaskActivityPinView.as_view()),
    path('tasks/<int:task_id>/attachments', TaskAttachmentCreateView.as_view()),
    path('attachments/<int:attachment_id>/download', TaskAttachmentDownloadView.as_view()),
    path('assignees', AssignableMemberView.as_view()),
    path('dashboard', TaskDashboardView.as_view()),
    path('reports', TaskReportView.as_view()),
    path('notifications', TaskNotificationView.as_view()),
    path('notifications/read', TaskNotificationReadView.as_view()),
    path('notifications/<int:notification_id>/read', TaskNotificationReadView.as_view()),
    path('kpi-summary', KpiSummaryView.as_view()),
    path('kpi-goals', KpiGoalListCreateView.as_view()),
    path('kpi-goals/<int:goal_id>', KpiGoalDetailView.as_view()),
]
