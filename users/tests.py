import base64

from django.contrib.auth import get_user_model
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from chat.models import Conversation, ConversationParticipant
from users.models import UserDevice


User = get_user_model()
VALID_PUBLIC_KEY_1 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
VALID_PUBLIC_KEY_2 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
VALID_PQC_PUBLIC_KEY = base64.b64encode(bytes(1184)).decode()
VALID_PQC_SIGNING_PUBLIC_KEY = base64.b64encode(bytes(1952)).decode()


class AuthApiTests(APITestCase):
    def test_login_creates_user_and_device_binding(self):
        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'device_name': 'flutter-android',
                'platform': 'android',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['username'], 'ali')
        user_id = response.data['account_id']
        self.assertTrue(Token.objects.filter(user_id=user_id).exists())
        self.assertTrue(
            UserDevice.objects.filter(
                device_id='device-1',
                user_id=user_id,
                identity_public_key=VALID_PUBLIC_KEY_1,
                key_algorithm='x25519',
                pqc_public_key=VALID_PQC_PUBLIC_KEY,
                pqc_algorithm='ml-kem-768',
                pqc_signing_public_key=VALID_PQC_SIGNING_PUBLIC_KEY,
                pqc_signing_algorithm='ml-dsa-65',
            ).exists()
        )
        self.assertEqual(
            response.data['user']['devices'][0]['pqc_algorithm'],
            'ml-kem-768',
        )
        self.assertEqual(
            response.data['user']['devices'][0]['pqc_signing_algorithm'],
            'ml-dsa-65',
        )
        self.assertTrue(
            ConversationParticipant.objects.filter(
                conversation__title='General Group',
                user_id=user_id,
            ).exists()
        )

    def test_login_preserves_display_name_while_normalizing_username(self):
        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'Riley Reid',
                'device_id': 'device-riley',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['user']['username'], 'Riley Reid')
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

    def test_same_device_reuses_existing_account_binding(self):
        first = self.client.post(
            '/api/auth/login',
            {'username': 'ali', 'device_id': 'device-1'},
            format='json',
        )

        response = self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-1'},
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['account_id'], first.data['account_id'])
        self.assertEqual(response.data['user']['display_name'], 'vali')

    def test_existing_device_public_key_is_updated(self):
        self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': VALID_PUBLIC_KEY_2,
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, VALID_PUBLIC_KEY_2)

    def test_same_display_name_on_different_devices_creates_distinct_accounts(self):
        first = self.client.post(
            '/api/auth/login',
            {'display_name': 'Riley', 'device_id': 'device-1'},
            format='json',
        )
        second = self.client.post(
            '/api/auth/login',
            {'display_name': 'Riley', 'device_id': 'device-2'},
            format='json',
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertNotEqual(first.data['account_id'], second.data['account_id'])

    def test_authenticated_device_sync_updates_registered_device(self):
        login = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': VALID_PUBLIC_KEY_1,
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
                'identity_public_key': VALID_PUBLIC_KEY_2,
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, VALID_PUBLIC_KEY_2)
        self.assertEqual(device.platform, 'android')

    def test_login_rejects_invalid_x25519_public_key(self):
        response = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': 'not-base64',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('identity_public_key', str(response.data))

    def test_device_sync_rejects_invalid_x25519_public_key(self):
        login = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
            },
            format='json',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")

        response = self.client.post(
            '/api/users/me/device',
            {
                'device_id': 'device-1',
                'identity_public_key': 'broken-key',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('identity_public_key', str(response.data))
