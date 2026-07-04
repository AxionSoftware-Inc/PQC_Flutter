from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from chat.models import Conversation, ConversationParticipant
from users.models import UserDevice


User = get_user_model()


class AuthApiTests(APITestCase):
    def test_login_creates_user_and_device_binding(self):
        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'device_name': 'flutter-android',
                'platform': 'android',
                'identity_public_key': 'public-key-1',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['username'], 'ali')
        self.assertTrue(Token.objects.filter(user__username='ali').exists())
        self.assertTrue(
            UserDevice.objects.filter(
                device_id='device-1',
                user__username='ali',
                identity_public_key='public-key-1',
                key_algorithm='x25519',
            ).exists()
        )
        self.assertTrue(
            ConversationParticipant.objects.filter(
                conversation__title='General Group',
                user__username='ali',
            ).exists()
        )

    def test_login_preserves_display_name_while_normalizing_username(self):
        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'Riley Reid',
                'device_id': 'device-riley',
                'identity_public_key': 'public-key-riley',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['username'], 'riley reid')
        self.assertEqual(response.data['user']['display_name'], 'Riley Reid')

    def test_me_returns_authenticated_user(self):
        login = self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-2'},
            format='json',
        )
        token = login.data['token']
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {token}')

        response = self.client.get('/api/users/me')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['username'], 'vali')

    def test_users_endpoint_returns_created_users(self):
        self.client.post('/api/auth/login', {'username': 'ali', 'device_id': 'device-1'}, format='json')
        login = self.client.post('/api/auth/login', {'username': 'vali', 'device_id': 'device-2'}, format='json')
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")

        response = self.client.get('/api/users')

        self.assertEqual(response.status_code, 200)
        usernames = [item['username'] for item in response.data]
        self.assertEqual(usernames, ['ali', 'vali'])
        self.assertEqual(response.data[0]['devices'][0]['device_id'], 'device-1')
        self.assertEqual(response.data[1]['devices'][0]['device_id'], 'device-2')

    def test_same_device_cannot_claim_another_username(self):
        self.client.post('/api/auth/login', {'username': 'ali', 'device_id': 'device-1'}, format='json')

        response = self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-1'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'This device is already linked to another username.',
        )

    def test_existing_device_public_key_is_updated(self):
        self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': 'public-key-1',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': 'public-key-2',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, 'public-key-2')

    def test_authenticated_device_sync_updates_registered_device(self):
        login = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': 'public-key-1',
                'key_algorithm': 'x25519',
            },
            format='json',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")

        response = self.client.post(
            '/api/users/me/device',
            {
                'device_id': 'device-1',
                'device_name': 'flutter-android',
                'platform': 'android',
                'identity_public_key': 'public-key-2',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, 'public-key-2')
        self.assertEqual(device.platform, 'android')
