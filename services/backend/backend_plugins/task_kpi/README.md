# Task & KPI plugin

This is an optional tenant module. The chat, crypto and recovery core do not
import it. Enable it explicitly on the backend:

```sh
ANTIQ_BACKEND_PLUGINS=task_kpi
python services/backend/manage.py migrate
```

The mobile task surface is enabled with the existing `TASK_KPI_MODULE` build
flag. The backend is authoritative for permissions and allowed state changes.

## Boundaries

- `workflow.py` owns status transitions.
- `permissions.py` owns task participant and hierarchy checks.
- `activity.py` records append-only task timeline events and creates the
  in-app notification inbox entries.
- Views are transport-only: they call those policy services and never accept
  role decisions from the client.

## API surface

- `GET/POST /api/task-kpi/tasks` — scoped task list and creation.
- `PATCH /api/task-kpi/tasks/:id` — approved workflow transition only.
- `PATCH /api/task-kpi/tasks/:id/manage` — deadline, priority, assignee,
  watchers, or separate cancellation with a reason.
- `GET/POST /api/task-kpi/tasks/:id/activity` — task conversation/timeline.
- `POST /api/task-kpi/tasks/:id/conversation` — durable app-chat conversation
  scoped to this task; KPI conversations never appear in the normal private
  chat list.
- `POST /api/task-kpi/tasks/:id/attachments` — authenticated file, image, or
  audio-file upload. Downloads use an authenticated endpoint rather than a
  raw media URL.
- `GET /api/task-kpi/dashboard`, `GET /api/task-kpi/reports` and
  `?format=csv` — operational reporting.
- `GET /api/task-kpi/notifications` — in-app inbox; `POST .../read` marks it
  read.

Push delivery is intentionally separate from this plugin: a deployed mobile
push provider should consume `TaskNotification` records or the corresponding
activity events. It cannot be safely enabled without the tenant's FCM/APNs
credentials and delivery policy.
