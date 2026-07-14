import base64
import unittest
from concurrent.futures import ThreadPoolExecutor
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.db import close_old_connections, connection
from django.test import TransactionTestCase
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient, APITestCase

from chat.models import Conversation, ConversationParticipant
from users.models import UserDevice
from users.models import AccountKeysetEscrowRecord, AccountRecoveryManifest
from users.escrow import LocalDevelopmentEscrowProvider


User = get_user_model()
VALID_PUBLIC_KEY_1 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
VALID_PUBLIC_KEY_2 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
VALID_PQC_PUBLIC_KEY = base64.b64encode(bytes(1184)).decode()
VALID_PQC_SIGNING_PUBLIC_KEY = base64.b64encode(bytes(1952)).decode()


class RecoveryManifestOCCIntegrationTests(APITestCase):
    """Virtual-device tests for the recovery endpoint's OCC contract."""

    def setUp(self):
        self.user = User.objects.create_user(username='recovery-owner')
        self.client.force_authenticate(self.user)

    def _put(self, *, device_id, payload, expected_sequence):
        return self.client.put(
            '/api/users/me/crypto-recovery',
            {
                'schema_version': 2,
                'source_device_id': device_id,
                'expected_sequence': expected_sequence,
                'payload': payload,
            },
            format='json',
            HTTP_X_DEVICE_ID=device_id,
        )

    def test_twenty_virtual_devices_with_same_snapshot_get_one_commit_and_412_conflicts(self):
        # All 20 clients read sequence=0, then race to publish.  The first
        # commit wins; every stale write must be an explicit 412, never a
        # silent overwrite.
        responses = [
            self._put(
                device_id=f'virtual-device-{index}',
                payload=f'{{"device":{index},"manifest":"v2"}}',
                expected_sequence=0,
            )
            for index in range(20)
        ]
        self.assertEqual(sum(item.status_code == 200 for item in responses), 1)
        self.assertEqual(sum(item.status_code == 412 for item in responses), 19)
        self.assertTrue(
            all(
                item.status_code == 200
                or item.data.get('code') == 'recovery_manifest_conflict'
                for item in responses
            )
        )
        manifest = AccountRecoveryManifest.objects.get(user=self.user)
        self.assertEqual(manifest.sequence, 1)
        self.assertEqual(AccountKeysetEscrowRecord.objects.filter(user=self.user).count(), 1)
        metrics = self.client.get('/api/users/me/crypto-observability')
        self.assertEqual(metrics.status_code, 200)
        self.assertEqual(metrics.data['manifest_sync_conflict_count'], 19)

    def test_one_hundred_relogin_reinstall_recovery_cycles_keep_every_immutable_record(self):
        sequence = 0
        expected_payloads = set()
        for index in range(100):
            payload = f'{{"cycle":{index},"keyset":"historical-{index}"}}'
            response = self._put(
                device_id=f'reinstall-device-{index % 7}',
                payload=payload,
                expected_sequence=sequence,
            )
            self.assertEqual(response.status_code, 200, response.data)
            sequence = response.data['sequence']
            expected_payloads.add(payload)

            # A fresh virtual install can fetch and decrypt the entire escrow
            # ledger; the latest record must always be readable.
            recovery = self.client.get(
                '/api/users/me/crypto-recovery',
                HTTP_X_DEVICE_ID=f'reinstalled-{index}',
            )
            self.assertEqual(recovery.status_code, 200, recovery.data)
            recovered_payloads = {record['payload'] for record in recovery.data['records']}
            self.assertIn(payload, recovered_payloads)

        manifest = AccountRecoveryManifest.objects.get(user=self.user)
        self.assertEqual(manifest.sequence, 100)
        self.assertEqual(
            {record.payload_sha256 for record in AccountKeysetEscrowRecord.objects.filter(user=self.user)}.__len__(),
            100,
        )

    def test_chaos_escrow_upload_failure_rolls_back_without_partial_manifest(self):
        with patch('users.views.get_key_escrow_provider', return_value=_FailingEscrowProvider()):
            response = self._put(
                device_id='chaos-device',
                payload='{"chaos":"network-or-kms-failure"}',
                expected_sequence=0,
            )
        self.assertEqual(response.status_code, 500)
        self.assertFalse(AccountRecoveryManifest.objects.filter(user=self.user).exists())
        self.assertFalse(AccountKeysetEscrowRecord.objects.filter(user=self.user).exists())

    def test_split_brain_client_force_pulls_then_replays_its_unsynced_change(self):
        # A is offline with sequence=0. B writes first; A's stale write is
        # rejected, then it pulls B's sequence and replays its own change.
        device_b = self._put(device_id='wifi-device-b', payload='{"B":1}', expected_sequence=0)
        self.assertEqual(device_b.status_code, 200)
        stale_a = self._put(device_id='offline-device-a', payload='{"A":1}', expected_sequence=0)
        self.assertEqual(stale_a.status_code, 412)
        latest = self.client.get('/api/users/me/crypto-recovery')
        replay_a = self._put(
            device_id='offline-device-a',
            payload='{"A":1}',
            expected_sequence=latest.data['sequence'],
        )
        self.assertEqual(replay_a.status_code, 200)
        self.assertEqual(AccountRecoveryManifest.objects.get(user=self.user).sequence, 2)
        self.assertEqual(AccountKeysetEscrowRecord.objects.filter(user=self.user).count(), 2)

    def test_tampered_envelope_is_rejected_by_aes_gcm_authentication(self):
        provider = LocalDevelopmentEscrowProvider()
        envelope = provider.encrypt(account_id=self.user.id, plaintext='must-not-garble')
        corrupted = envelope.__class__(
            encrypted_data_key=envelope.encrypted_data_key,
            ciphertext=('A' if envelope.ciphertext[0] != 'A' else 'B') + envelope.ciphertext[1:],
            nonce=envelope.nonce,
            key_id=envelope.key_id,
            encryption_context=envelope.encryption_context,
        )
        with self.assertRaises(ValueError):
            provider.decrypt(account_id=self.user.id, envelope=corrupted)


@unittest.skipUnless(
    connection.vendor == 'postgresql',
    'True parallel write test requires PostgreSQL row-lock semantics.',
)
class RecoveryManifestParallelDatabaseTests(TransactionTestCase):
    """Runs 20 requests concurrently against independent DB connections."""

    def setUp(self):
        self.user = User.objects.create_user(username='parallel-recovery-owner')

    def _publish(self, index, barrier):
        close_old_connections()
        try:
            client = APIClient()
            client.force_authenticate(User.objects.get(pk=self.user.pk))
            barrier.wait(timeout=10)
            response = client.put(
                '/api/users/me/crypto-recovery',
                {
                    'schema_version': 2,
                    'source_device_id': f'parallel-device-{index}',
                    'expected_sequence': 0,
                    'payload': f'{{"parallel_device":{index}}}',
                },
                format='json',
                HTTP_X_DEVICE_ID=f'parallel-device-{index}',
            )
            return response.status_code, response.data
        finally:
            close_old_connections()

    def test_twenty_real_parallel_writers_preserve_the_immutable_ledger(self):
        from threading import Barrier

        barrier = Barrier(20)
        with ThreadPoolExecutor(max_workers=20) as executor:
            results = list(executor.map(lambda index: self._publish(index, barrier), range(20)))

        self.assertEqual(sum(status == 200 for status, _ in results), 1)
        self.assertEqual(sum(status == 412 for status, _ in results), 19)
        self.assertTrue(
            all(
                status == 200 or payload.get('code') == 'recovery_manifest_conflict'
                for status, payload in results
            )
        )
        self.assertEqual(AccountRecoveryManifest.objects.get(user=self.user).sequence, 1)
        self.assertEqual(AccountKeysetEscrowRecord.objects.filter(user=self.user).count(), 1)


class _FailingEscrowProvider:
    def encrypt(self, **_):
        raise RuntimeError('simulated escrow upload interruption')


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
        self.assertEqual(response.data['device_status'], 'active')
        self.assertTrue(response.data['profile_fingerprint'])
        self.assertEqual(len(response.data['active_devices']), 1)
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

    def test_existing_device_public_key_change_is_rejected(self):
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

        self.assertEqual(response.status_code, 409)
        self.assertEqual(response.data['code'], 'device_profile_mismatch')
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, VALID_PUBLIC_KEY_1)

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

    def test_remember_device_only_reuses_account_for_same_device_name(self):
        first = self.client.post(
            '/api/auth/login',
            {
                'username': 'Ali',
                'device_id': 'device-1',
                'device_name': 'Samsung SM-S918B',
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

        second = self.client.post(
            '/api/auth/login',
            {
                'display_name': 'Samsung SM-S918B',
                'remember_device_only': True,
                'device_id': 'device-2',
                'device_name': 'Samsung SM-S918B',
                'platform': 'android',
                'identity_public_key': VALID_PUBLIC_KEY_2,
                'key_algorithm': 'x25519',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.data['account_id'], first.data['account_id'])
        self.assertTrue(
            UserDevice.objects.filter(
                user_id=first.data['account_id'],
                device_id='device-2',
            ).exists()
        )

    def test_authenticated_device_sync_updates_presence_only(self):
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
            '/api/users/me/device/sync',
            {
                'device_id': 'device-1',
                'device_name': 'flutter-android',
                'platform': 'android',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 200)
        device = UserDevice.objects.get(device_id='device-1')
        self.assertEqual(device.identity_public_key, VALID_PUBLIC_KEY_1)
        self.assertEqual(device.platform, 'android')
        self.assertEqual(response.data['device_status'], 'active')

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
            '/api/users/me/device/sync',
            {
                'device_id': 'device-1',
                'identity_public_key': 'broken-key',
                'key_algorithm': 'x25519',
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('identity_public_key', str(response.data))

    def test_device_list_only_returns_active_devices(self):
        login = self.client.post(
            '/api/auth/login',
            {'username': 'ali', 'device_id': 'device-1'},
            format='json',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")
        UserDevice.objects.create(
            user_id=login.data['account_id'],
            device_id='device-2',
            status=UserDevice.Status.REVOKED,
        )

        response = self.client.get('/api/users/me/devices')

        self.assertEqual(response.status_code, 200)
        self.assertEqual([item['device_id'] for item in response.data], ['device-1'])


class AccountSettingsSyncTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='settings-owner')
        self.client.force_authenticate(self.user)

    def test_settings_round_trip_survives_fresh_client_load(self):
        updated = self.client.patch(
            '/api/users/me/settings',
            {
                'notifications_enabled': False,
                'read_receipts_enabled': False,
                'typing_indicators_enabled': False,
                'last_seen_visibility': 'nobody',
            },
            format='json',
        )
        self.assertEqual(updated.status_code, 200, updated.data)

        fresh_read = self.client.get('/api/users/me/settings')
        self.assertEqual(fresh_read.status_code, 200, fresh_read.data)
        self.assertFalse(fresh_read.data['notifications_enabled'])
        self.assertFalse(fresh_read.data['read_receipts_enabled'])
        self.assertFalse(fresh_read.data['typing_indicators_enabled'])
        self.assertEqual(fresh_read.data['last_seen_visibility'], 'nobody')
