from io import StringIO

from django.contrib.auth import get_user_model
from django.core.management import call_command
from django.core.management.base import CommandError
from rest_framework.test import APITestCase

from users.access_control.catalog import AccessPermission
from users.models import (
    Organization,
    OrganizationMember,
    Workspace,
    WorkspaceMember,
)
from users.roles import CorporateRole


User = get_user_model()


class WorkspaceAccessControlTests(APITestCase):
    def setUp(self):
        self.owner = User.objects.create_user(username='owner')
        self.member_user = User.objects.create_user(username='member')
        self.organization = Organization.objects.create(
            name='antiQ Test',
            slug='antiq-test',
            created_by=self.owner,
        )
        self.workspace = Workspace.objects.create(
            organization=self.organization,
            name='Main',
            slug='main',
            is_default=True,
        )
        owner_org_member = OrganizationMember.objects.create(
            organization=self.organization,
            user=self.owner,
            role=CorporateRole.OWNER,
        )
        member_org_member = OrganizationMember.objects.create(
            organization=self.organization,
            user=self.member_user,
            role=CorporateRole.MEMBER,
        )
        self.owner_membership = WorkspaceMember.objects.create(
            workspace=self.workspace,
            organization_member=owner_org_member,
            role=CorporateRole.OWNER,
        )
        self.member_membership = WorkspaceMember.objects.create(
            workspace=self.workspace,
            organization_member=member_org_member,
            role=CorporateRole.MEMBER,
        )

    def _workspace_headers(self):
        return {'HTTP_X_WORKSPACE_ID': str(self.workspace.id)}

    def test_owner_can_create_and_assign_a_custom_role(self):
        self.client.force_authenticate(self.owner)
        create_response = self.client.post(
            '/api/rbac/roles',
            {
                'key': 'security-auditor',
                'name': 'Xavfsizlik auditori',
                'description': 'Audit va xavfsizlik holatini ko‘radi.',
                'permissions': [
                    AccessPermission.AUDIT_VIEW,
                    AccessPermission.SECURITY_VIEW,
                ],
            },
            format='json',
            **self._workspace_headers(),
        )
        self.assertEqual(create_response.status_code, 201)

        assignment_response = self.client.post(
            '/api/rbac/assignments',
            {
                'workspace_member_id': self.member_membership.id,
                'role_id': create_response.data['id'],
            },
            format='json',
            **self._workspace_headers(),
        )
        self.assertEqual(assignment_response.status_code, 201)

        self.client.force_authenticate(self.member_user)
        snapshot = self.client.get(
            '/api/rbac/me',
            **self._workspace_headers(),
        )
        self.assertEqual(snapshot.status_code, 200)
        self.assertIn('security-auditor', snapshot.data['custom_roles'])
        self.assertIn(AccessPermission.AUDIT_VIEW, snapshot.data['permissions'])
        self.assertIn(
            AccessPermission.MESSAGES_SEND,
            snapshot.data['permissions'],
        )

    def test_member_cannot_manage_roles(self):
        self.client.force_authenticate(self.member_user)
        response = self.client.post(
            '/api/rbac/roles',
            {
                'key': 'unauthorized',
                'name': 'Unauthorized',
                'permissions': [],
            },
            format='json',
            **self._workspace_headers(),
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(
            response.data['required_permission'],
            AccessPermission.ROLES_MANAGE,
        )

    def test_unknown_permission_is_rejected(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(
            '/api/rbac/roles',
            {
                'key': 'invalid',
                'name': 'Invalid',
                'permissions': ['messages.read_plaintext'],
            },
            format='json',
            **self._workspace_headers(),
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn('permissions', response.data['errors'])

    def test_catalog_exposes_stable_built_in_roles(self):
        self.client.force_authenticate(self.owner)
        response = self.client.get(
            '/api/rbac/catalog',
            **self._workspace_headers(),
        )
        self.assertEqual(response.status_code, 200)
        role_keys = {item['key'] for item in response.data['built_in_roles']}
        self.assertEqual(role_keys, {'owner', 'admin', 'manager', 'member'})
        permission_codes = {
            item['code'] for item in response.data['permissions']
        }
        self.assertIn(AccessPermission.ROLES_MANAGE, permission_codes)
        self.assertNotIn('messages.read_plaintext', permission_codes)

    def test_custom_permission_is_enforced_by_existing_invitation_endpoint(self):
        self.client.force_authenticate(self.owner)
        role = self.client.post(
            '/api/rbac/roles',
            {
                'key': 'recruiter',
                'name': 'Recruiter',
                'permissions': [AccessPermission.MEMBERS_INVITE],
            },
            format='json',
            **self._workspace_headers(),
        )
        self.client.post(
            '/api/rbac/assignments',
            {
                'workspace_member_id': self.member_membership.id,
                'role_id': role.data['id'],
            },
            format='json',
            **self._workspace_headers(),
        )

        self.client.force_authenticate(self.member_user)
        response = self.client.post(
            '/api/invitations',
            {
                'workspace_id': self.workspace.id,
                'email': 'new.member@example.com',
                'role': CorporateRole.MEMBER,
            },
            format='json',
            **self._workspace_headers(),
        )
        self.assertEqual(response.status_code, 201)

    def test_owner_grant_command_is_scoped_to_existing_memberships(self):
        self.member_user.email = 'axionsoftwareindustries@gmail.com'
        self.member_user.save(update_fields=['email'])
        output = StringIO()

        call_command(
            'grant_workspace_owner',
            email='axionsoftwareindustries@gmail.com',
            stdout=output,
        )

        self.member_membership.refresh_from_db()
        self.member_membership.organization_member.refresh_from_db()
        self.assertEqual(self.member_membership.role, CorporateRole.OWNER)
        self.assertEqual(
            self.member_membership.organization_member.role,
            CorporateRole.OWNER,
        )
        self.assertIn('Granted Owner', output.getvalue())

    def test_owner_grant_command_rejects_an_unknown_account(self):
        with self.assertRaises(CommandError):
            call_command(
                'grant_workspace_owner',
                email='missing@example.com',
            )
