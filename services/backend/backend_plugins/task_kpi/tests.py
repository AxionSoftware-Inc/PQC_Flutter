from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework.test import APITestCase

from users.models import Organization, OrganizationMember, Workspace, WorkspaceMember


User = get_user_model()


class TaskKpiPluginTests(APITestCase):
    def setUp(self):
        self.manager = User.objects.create_user(username='manager', password='x')
        self.worker = User.objects.create_user(username='worker', password='x')
        self.observer = User.objects.create_user(username='observer', password='x')
        organization = Organization.objects.create(name='Acme', slug='acme')
        self.workspace = Workspace.objects.create(organization=organization, name='HQ', slug='hq', is_default=True)
        manager_org = OrganizationMember.objects.create(organization=organization, user=self.manager, role='admin')
        worker_org = OrganizationMember.objects.create(organization=organization, user=self.worker, role='member')
        self.manager_member = WorkspaceMember.objects.create(workspace=self.workspace, organization_member=manager_org, role='admin')
        self.worker_member = WorkspaceMember.objects.create(workspace=self.workspace, organization_member=worker_org, role='member')
        observer_org = OrganizationMember.objects.create(organization=organization, user=self.observer, role='member')
        self.observer_member = WorkspaceMember.objects.create(workspace=self.workspace, organization_member=observer_org, role='member')
        self.headers = {'HTTP_X_WORKSPACE_ID': str(self.workspace.id)}

    def test_manager_creates_task_and_worker_updates_own_status(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post('/api/task-kpi/tasks', {'title': 'Hisobot', 'assignee_id': self.worker_member.id}, format='json', **self.headers)
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data['available_actions'], [])
        self.client.force_authenticate(self.worker)
        own_tasks = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertEqual([item['id'] for item in own_tasks.data], [created.data['id']])
        self.assertEqual(own_tasks.data[0]['available_actions'], ['accept'])
        accepted = self.client.patch(f"/api/task-kpi/tasks/{created.data['id']}", {'status': 'accepted'}, format='json', **self.headers)
        self.assertEqual(accepted.status_code, 200)
        self.assertEqual(accepted.data['available_actions'], ['start'])
        started = self.client.patch(f"/api/task-kpi/tasks/{created.data['id']}", {'status': 'in_progress'}, format='json', **self.headers)
        self.assertEqual(started.status_code, 200)
        self.assertEqual(started.data['available_actions'], ['submit'])
        updated = self.client.patch(f"/api/task-kpi/tasks/{created.data['id']}", {'status': 'submitted', 'completion_note': 'Tayyor'}, format='json', **self.headers)
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.data['status'], 'submitted')
        self.assertEqual(updated.data['available_actions'], [])

    def test_only_assignee_sees_work_actions_and_manager_only_sees_review_actions(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post('/api/task-kpi/tasks', {'title': 'Hisobot', 'assignee_id': self.worker_member.id}, format='json', **self.headers)
        task_url = f"/api/task-kpi/tasks/{created.data['id']}"

        # A manager can see the task but must not receive the employee's
        # accept/start/submit controls.
        manager_view = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertEqual(manager_view.data[0]['available_actions'], [])
        invalid = self.client.patch(task_url, {'status': 'in_progress'}, format='json', **self.headers)
        self.assertEqual(invalid.status_code, 409)

        self.client.force_authenticate(self.worker)
        self.assertEqual(self.client.patch(task_url, {'status': 'accepted'}, format='json', **self.headers).status_code, 200)
        self.assertEqual(self.client.patch(task_url, {'status': 'in_progress'}, format='json', **self.headers).status_code, 200)
        submitted = self.client.patch(task_url, {'status': 'submitted', 'completion_note': 'Tayyor'}, format='json', **self.headers)
        self.assertEqual(submitted.status_code, 200)

        self.client.force_authenticate(self.manager)
        manager_view = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertEqual(manager_view.data[0]['available_actions'], ['approve', 'return'])

    def test_activity_attachments_notifications_and_watcher_access(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post('/api/task-kpi/tasks', {
            'title': 'Hisobot',
            'assignee_id': self.worker_member.id,
            'watcher_ids': [self.observer_member.id],
        }, format='json', **self.headers)
        self.assertEqual(created.status_code, 201)
        task_id = created.data['id']

        self.client.force_authenticate(self.worker)
        comment = self.client.post(
            f'/api/task-kpi/tasks/{task_id}/activity',
            {'body': 'Raqamlarni aniqlashtirib bering.'},
            format='json',
            **self.headers,
        )
        self.assertEqual(comment.status_code, 201)
        upload = self.client.post(
            f'/api/task-kpi/tasks/{task_id}/attachments',
            {'file': SimpleUploadedFile('hisobot.txt', b'test')},
            **self.headers,
        )
        self.assertEqual(upload.status_code, 201)
        self.assertEqual(upload.data['url'], f"/task-kpi/attachments/{upload.data['id']}/download")
        file_reply = self.client.post(
            f'/api/task-kpi/tasks/{task_id}/activity',
            {
                'body': 'Hisobot fayliga izoh.',
                'metadata': {'reply_to_attachment_id': upload.data['id']},
            },
            format='json',
            **self.headers,
        )
        self.assertEqual(file_reply.status_code, 201)
        self.assertEqual(
            file_reply.data['metadata']['reply_to_attachment_id'],
            upload.data['id'],
        )
        pin = self.client.post(
            f'/api/task-kpi/tasks/{task_id}/activity/{file_reply.data["id"]}/pin',
            {'pinned': True},
            format='json',
            **self.headers,
        )
        self.assertEqual(pin.status_code, 200)
        self.assertTrue(pin.data['is_pinned'])

        self.client.force_authenticate(self.observer)
        visible = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertEqual([item['id'] for item in visible.data], [task_id])
        observer_comment = self.client.post(
            f'/api/task-kpi/tasks/{task_id}/activity',
            {'body': 'Men ham kuzatyapman.'},
            format='json',
            **self.headers,
        )
        self.assertEqual(observer_comment.status_code, 201)

        self.client.force_authenticate(self.manager)
        notifications = self.client.get('/api/task-kpi/notifications', **self.headers)
        self.assertGreaterEqual(notifications.data['unread_count'], 2)
        activity = self.client.get(f'/api/task-kpi/tasks/{task_id}/activity', **self.headers)
        self.assertGreaterEqual(len(activity.data), 4)

    def test_manager_can_cancel_with_reason_and_cancelled_task_rejects_comments(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post('/api/task-kpi/tasks', {'title': 'Hisobot', 'assignee_id': self.worker_member.id}, format='json', **self.headers)
        cancelled = self.client.patch(
            f"/api/task-kpi/tasks/{created.data['id']}/manage",
            {'cancellation_note': 'Ushbu hisobot endi kerak emas.'},
            format='json',
            **self.headers,
        )
        self.assertEqual(cancelled.status_code, 200)
        self.assertEqual(cancelled.data['status'], 'cancelled')

        self.client.force_authenticate(self.worker)
        comment = self.client.post(
            f"/api/task-kpi/tasks/{created.data['id']}/activity",
            {'body': 'Yubora olmayman.'},
            format='json',
            **self.headers,
        )
        self.assertEqual(comment.status_code, 403)

    def test_task_list_supports_bounded_pagination_without_changing_legacy_shape(self):
        self.client.force_authenticate(self.manager)
        for index in range(3):
            response = self.client.post(
                '/api/task-kpi/tasks',
                {'title': f'Hisobot {index}', 'assignee_id': self.worker_member.id},
                format='json',
                **self.headers,
            )
            self.assertEqual(response.status_code, 201)
        page = self.client.get('/api/task-kpi/tasks?offset=0&limit=2', **self.headers)
        self.assertEqual(page.status_code, 200)
        self.assertEqual(len(page.data['items']), 2)
        self.assertTrue(page.data['has_more'])
        legacy = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertIsInstance(legacy.data, list)

    def test_dashboard_and_report_return_scoped_metrics(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post(
            '/api/task-kpi/tasks',
            {'title': 'Haftalik KPI', 'assignee_id': self.worker_member.id},
            format='json',
            **self.headers,
        )
        self.assertEqual(created.status_code, 201)

        dashboard = self.client.get('/api/task-kpi/dashboard', **self.headers)
        self.assertEqual(dashboard.status_code, 200)
        self.assertEqual(dashboard.data['assigned_by_me_open'], 1)
        self.assertIn('team', dashboard.data)

        report = self.client.get('/api/task-kpi/reports', **self.headers)
        self.assertEqual(report.status_code, 200)
        self.assertEqual(report.data['total'], 1)
        self.assertEqual(report.data['done'], 0)
