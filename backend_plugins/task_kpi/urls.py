from django.urls import path

from .views import KpiGoalListCreateView, TaskDetailView, TaskListCreateView

urlpatterns = [
    path('tasks', TaskListCreateView.as_view()),
    path('tasks/<int:task_id>', TaskDetailView.as_view()),
    path('kpi-goals', KpiGoalListCreateView.as_view()),
]
