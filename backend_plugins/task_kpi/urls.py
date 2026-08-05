from django.urls import path

from .views import AssignableMemberView, KpiGoalListCreateView, KpiSummaryView, TaskAttachmentCreateView, TaskDetailView, TaskListCreateView

urlpatterns = [
    path('tasks', TaskListCreateView.as_view()),
    path('tasks/<int:task_id>', TaskDetailView.as_view()),
    path('tasks/<int:task_id>/attachments', TaskAttachmentCreateView.as_view()),
    path('assignees', AssignableMemberView.as_view()),
    path('kpi-summary', KpiSummaryView.as_view()),
    path('kpi-goals', KpiGoalListCreateView.as_view()),
]
