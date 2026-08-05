from django.contrib.auth import get_user_model
from rest_framework.test import APITestCase

from users.models import Organization, OrganizationMember, Workspace, WorkspaceMember


User = get_user_model()


class TaskKpiPluginTests(APITestCase):
    def setUp(self):
        self.manager = User.objects.create_user(username='manager', password='x')
        self.worker = User.objects.create_user(username='worker', password='x')
        organization = Organization.objects.create(name='Acme', slug='acme')
        self.workspace = Workspace.objects.create(organization=organization, name='HQ', slug='hq', is_default=True)
        manager_org = OrganizationMember.objects.create(organization=organization, user=self.manager, role='admin')
        worker_org = OrganizationMember.objects.create(organization=organization, user=self.worker, role='member')
        self.manager_member = WorkspaceMember.objects.create(workspace=self.workspace, organization_member=manager_org, role='admin')
        self.worker_member = WorkspaceMember.objects.create(workspace=self.workspace, organization_member=worker_org, role='member')
        self.headers = {'HTTP_X_WORKSPACE_ID': str(self.workspace.id)}

    def test_manager_creates_task_and_worker_updates_own_status(self):
        self.client.force_authenticate(self.manager)
        created = self.client.post('/api/task-kpi/tasks', {'title': 'Hisobot', 'assignee_id': self.worker_member.id}, format='json', **self.headers)
        self.assertEqual(created.status_code, 201)
        self.client.force_authenticate(self.worker)
        own_tasks = self.client.get('/api/task-kpi/tasks', **self.headers)
        self.assertEqual([item['id'] for item in own_tasks.data], [created.data['id']])
        self.client.patch(f"/api/task-kpi/tasks/{created.data['id']}", {'status': 'in_progress'}, format='json', **self.headers)
        updated = self.client.patch(f"/api/task-kpi/tasks/{created.data['id']}", {'status': 'submitted', 'completion_note': 'Tayyor'}, format='json', **self.headers)
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.data['status'], 'submitted')
