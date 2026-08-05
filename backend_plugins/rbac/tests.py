from django.contrib.auth import get_user_model
from django.test import override_settings
from rest_framework.test import APITestCase

from users.models import Organization, OrganizationMember, Workspace, WorkspaceMember


User = get_user_model()


@override_settings()
class RbacPluginApiTests(APITestCase):
    def setUp(self):
        self.admin = User.objects.create_user(username='admin', password='x')
        self.manager = User.objects.create_user(username='manager', password='x')
        self.worker = User.objects.create_user(username='worker', password='x')
        organization = Organization.objects.create(name='Acme', slug='acme')
        self.workspace = Workspace.objects.create(organization=organization, name='HQ', slug='hq', is_default=True)
        self.admin_member = self._member(organization, self.admin, 'admin')
        self.manager_member = self._member(organization, self.manager, 'member')
        self.worker_member = self._member(organization, self.worker, 'member')
        self.client.force_authenticate(self.admin)

    def _member(self, organization, user, role):
        org_member = OrganizationMember.objects.create(organization=organization, user=user, role=role)
        return WorkspaceMember.objects.create(workspace=self.workspace, organization_member=org_member, role=role)

    @property
    def headers(self):
        return {'HTTP_X_WORKSPACE_ID': str(self.workspace.id)}

    def test_admin_can_create_role_assign_it_and_list_members(self):
        director = self.client.post('/api/rbac/roles', {'name': 'Direktor', 'rank': 1, 'visibility': 'all'}, format='json', **self.headers)
        manager = self.client.post('/api/rbac/roles', {'name': 'Menejer', 'rank': 10, 'visibility': 'lower'}, format='json', **self.headers)
        self.assertEqual(director.status_code, 201)
        self.assertEqual(manager.status_code, 201)
        assigned = self.client.put(f'/api/rbac/members/{self.manager_member.id}/role', {'role_id': manager.data['id']}, format='json', **self.headers)
        self.assertEqual(assigned.status_code, 200)
        members = self.client.get('/api/rbac/members', **self.headers)
        self.assertEqual(members.status_code, 200)
        self.assertEqual({item['member_id'] for item in members.data}, {self.admin_member.id, self.manager_member.id, self.worker_member.id})

    def test_manager_with_lower_visibility_cannot_see_higher_admin(self):
        manager_role = self.client.post('/api/rbac/roles', {'name': 'Menejer', 'rank': 10, 'visibility': 'lower'}, format='json', **self.headers).data
        self.client.put(f'/api/rbac/members/{self.manager_member.id}/role', {'role_id': manager_role['id']}, format='json', **self.headers)
        self.client.force_authenticate(self.manager)
        members = self.client.get('/api/rbac/members', **self.headers)
        self.assertEqual(members.status_code, 200)
        self.assertEqual({item['member_id'] for item in members.data}, {self.manager_member.id})
