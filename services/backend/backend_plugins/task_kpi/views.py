"""Compatibility exports for the task/KPI API view modules."""

from backend_plugins.task_kpi.api_views.activity import (
    TaskActivityPinView,
    TaskActivityView,
    TaskAttachmentCreateView,
    TaskAttachmentDownloadView,
)
from backend_plugins.task_kpi.api_views.chat import TaskConversationView
from backend_plugins.task_kpi.api_views.common import (
    _assignable_members,
    _can_assign,
    _get_task,
    _manager,
    _membership,
    _replace_watchers,
    _task_serializer_context,
    _visible_tasks,
)
from backend_plugins.task_kpi.api_views.kpi import (
    KpiGoalDetailView,
    KpiGoalListCreateView,
    KpiSummaryView,
)
from backend_plugins.task_kpi.api_views.notifications import (
    AssignableMemberView,
    TaskDashboardView,
    TaskNotificationReadView,
    TaskNotificationView,
    TaskReportView,
)
from backend_plugins.task_kpi.api_views.tasks import (
    TaskDetailView,
    TaskListCreateView,
    TaskManageView,
)
