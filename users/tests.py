import base64
import hashlib
import json
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import close_old_connections, connection
from django.test import TransactionTestCase, override_settings
from django.utils import timezone
from rest_framework.authtoken.models import Token
from rest_framework.test import APIClient, APITestCase

from chat.models import Conversation, ConversationParticipant
from users.models import GoogleAccount, UserDevice, WorkspaceMember
from users.models import (
    AccountKeysetEscrowRecord,
    AccountRecoveryManifest,
    RecoveryAccessGrant,
    RecoveryDeviceApproval,
)
from users.escrow import LocalDevelopmentEscrowProvider
from users.roles import CorporateRole


User = get_user_model()
VALID_PUBLIC_KEY_1 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
VALID_PUBLIC_KEY_2 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
VALID_PQC_PUBLIC_KEY = base64.b64encode(bytes(1184)).decode()
VALID_PQC_SIGNING_PUBLIC_KEY = base64.b64encode(bytes(1952)).decode()


@override_settings(
    CRYPTO_RECOVERY_REQUIRE_DEVICE_APPROVAL=False,
    CRYPTO_RECOVERY_REQUIRE_REGISTERED_DEVICE=False,
)
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
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.data['code'], 'recovery_escrow_unavailable')
        self.assertTrue(response.data['retryable'])
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
@override_settings(
    CRYPTO_RECOVERY_REQUIRE_DEVICE_APPROVAL=False,
    CRYPTO_RECOVERY_REQUIRE_REGISTERED_DEVICE=False,
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


class RecoveryAuthorizationTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(username='secured-recovery-owner')
        self.device_credential = 'secured-device-credential'
        self.device = UserDevice.objects.create(
            user=self.user,
            device_id='secured-device',
            recovery_credential_sha256=hashlib.sha256(
                self.device_credential.encode()
            ).hexdigest(),
        )
        self.client.force_authenticate(self.user)
        response = self.client.put(
            '/api/users/me/crypto-recovery',
            {
                'schema_version': 2,
                'source_device_id': self.device.device_id,
                'expected_sequence': 0,
                'payload': '{"secured":true}',
            },
            format='json',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(response.status_code, 200, response.data)

    def test_plain_login_token_cannot_read_recovery_material(self):
        response = self.client.get(
            '/api/users/me/crypto-recovery',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data['code'], 'recovery_approval_required')

    def test_device_id_spoof_without_device_credential_is_rejected(self):
        response = self.client.get(
            '/api/users/me/crypto-recovery?metadata_only=true',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL='wrong-device-secret',
        )
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.data['code'], 'recovery_device_inactive')

    def test_fresh_federated_grant_is_device_bound_and_one_use(self):
        raw_grant = 'one-use-recovery-proof'
        RecoveryAccessGrant.objects.create(
            user=self.user,
            device_id=self.device.device_id,
            token_sha256=hashlib.sha256(raw_grant.encode()).hexdigest(),
            expires_at=timezone.now() + timedelta(minutes=5),
        )
        first = self.client.get(
            '/api/users/me/crypto-recovery',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_GRANT=raw_grant,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(first.status_code, 200, first.data)
        self.assertEqual(first.data['records'][0]['payload'], '{"secured":true}')

        replay = self.client.get(
            '/api/users/me/crypto-recovery',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_GRANT=raw_grant,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(replay.status_code, 403)

    def test_metadata_read_never_returns_decrypted_records(self):
        response = self.client.get(
            '/api/users/me/crypto-recovery?metadata_only=true',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(response.status_code, 200, response.data)
        self.assertNotIn('records', response.data)
        self.assertEqual(len(response.data['record_hashes']), 1)

    def test_approved_device_challenge_is_one_use(self):
        approver = UserDevice.objects.create(
            user=self.user,
            device_id='trusted-approver',
        )
        approval = RecoveryDeviceApproval.objects.create(
            user=self.user,
            requester_device_id=self.device.device_id,
            approver_device_id=approver.device_id,
            status=RecoveryDeviceApproval.Status.APPROVED,
            challenge='approved-once',
            expires_at=timezone.now() + timedelta(minutes=5),
            approved_at=timezone.now(),
        )
        first = self.client.get(
            '/api/users/me/crypto-recovery?approval=approved-once',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(first.status_code, 200, first.data)
        approval.refresh_from_db()
        self.assertEqual(approval.status, RecoveryDeviceApproval.Status.USED)

        replay = self.client.get(
            '/api/users/me/crypto-recovery?approval=approved-once',
            HTTP_X_DEVICE_ID=self.device.device_id,
            HTTP_X_RECOVERY_DEVICE_CREDENTIAL=self.device_credential,
        )
        self.assertEqual(replay.status_code, 403)


class _FakeGoogleResponse:
    def __init__(self, claims):
        self._payload = json.dumps(claims).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False

    def read(self):
        return self._payload


class AuthApiTests(APITestCase):
    def test_google_login_issues_device_bound_one_use_recovery_proofs(self):
        claims = {
            'aud': '937305477350-n9h2s4e6ra9rvs6s1s95gel6p4ldl5tg.apps.googleusercontent.com',
            'email_verified': 'true',
            'sub': 'google-security-subject',
            'email': 'security@example.com',
            'name': 'Security User',
        }
        with patch('users.views.urlopen', return_value=_FakeGoogleResponse(claims)):
            response = self.client.post(
                '/api/auth/google',
                {
                    'id_token': 'fresh-google-id-token',
                    'device_id': 'google-secure-device',
                    'device_name': 'Android',
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
        self.assertEqual(response.status_code, 200, response.data)
        self.assertTrue(response.data['recovery_grant'])
        self.assertTrue(response.data['recovery_device_credential'])
        device = UserDevice.objects.get(device_id='google-secure-device')
        self.assertEqual(
            device.recovery_credential_sha256,
            hashlib.sha256(
                response.data['recovery_device_credential'].encode()
            ).hexdigest(),
        )
        self.assertTrue(
            RecoveryAccessGrant.objects.filter(
                user=device.user,
                device_id=device.device_id,
                token_sha256=hashlib.sha256(
                    response.data['recovery_grant'].encode()
                ).hexdigest(),
                used_at__isnull=True,
            ).exists()
        )

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

    def test_users_endpoint_exposes_google_profile_picture(self):
        login = self.client.post(
            '/api/auth/login',
            {'username': 'avatar-user', 'device_id': 'avatar-device'},
            format='json',
        )
        user = User.objects.get(id=login.data['account_id'])
        GoogleAccount.objects.create(
            user=user,
            google_subject='google-avatar-subject',
            email='avatar@example.com',
            avatar_url='https://example.com/avatar.jpg',
        )
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {login.data['token']}",
        )
        response = self.client.get('/api/users')
        self.assertEqual(response.status_code, 200)
        avatar_user = next(item for item in response.data if item['id'] == user.id)
        self.assertEqual(avatar_user['avatar_url'], 'https://example.com/avatar.jpg')

    def test_users_endpoint_exposes_workspace_role_to_every_contact(self):
        owner = self.client.post(
            '/api/auth/login',
            {'username': 'owner', 'device_id': 'owner-device'},
            format='json',
        )
        member = self.client.post(
            '/api/auth/login',
            {'username': 'member', 'device_id': 'member-device'},
            format='json',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {owner.data['token']}")
        response = self.client.get('/api/users')
        self.assertEqual(response.status_code, 200)
        by_id = {item['id']: item for item in response.data}
        self.assertEqual(by_id[owner.data['account_id']]['role'], 'owner')
        self.assertEqual(by_id[owner.data['account_id']]['role_label'], 'Egasi')
        self.assertEqual(by_id[member.data['account_id']]['role'], 'member')
        self.assertEqual(by_id[member.data['account_id']]['role_label'], 'Xodim')

    def test_owner_can_assign_manager_role_and_member_cannot_escalate(self):
        owner = self.client.post(
            '/api/auth/login',
            {'username': 'owner', 'device_id': 'role-owner-device'},
            format='json',
        )
        member = self.client.post(
            '/api/auth/login',
            {'username': 'member', 'device_id': 'role-member-device'},
            format='json',
        )
        member_id = member.data['account_id']
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {owner.data['token']}")
        updated = self.client.put(
            f'/api/users/{member_id}/role',
            {'role': 'manager'},
            format='json',
        )
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.data['role'], 'manager')
        self.assertEqual(updated.data['role_label'], 'Menejer')
        self.assertEqual(
            WorkspaceMember.objects.get(
                organization_member__user_id=member_id,
            ).role,
            CorporateRole.MANAGER,
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {member.data['token']}")
        forbidden = self.client.put(
            f"/api/users/{owner.data['account_id']}/role",
            {'role': 'member'},
            format='json',
        )
        self.assertEqual(forbidden.status_code, 403)

    def test_user_can_update_display_name_and_override_google_avatar(self):
        login = self.client.post(
            '/api/auth/login',
            {'username': 'Old Name', 'device_id': 'profile-device'},
            format='json',
        )
        user = User.objects.get(id=login.data['account_id'])
        GoogleAccount.objects.create(
            user=user,
            google_subject='profile-google-subject',
            avatar_url='https://example.com/google-avatar.jpg',
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {login.data['token']}")
        renamed = self.client.patch(
            '/api/users/me',
            {'display_name': 'Yangi Ism'},
            format='json',
        )
        uploaded = self.client.post(
            '/api/users/me/avatar',
            {
                'avatar': SimpleUploadedFile(
                    'avatar.png',
                    b'profile-image-bytes',
                    content_type='image/png',
                ),
            },
            format='multipart',
        )
        self.assertEqual(renamed.status_code, 200)
        self.assertEqual(renamed.data['display_name'], 'Yangi Ism')
        self.assertEqual(uploaded.status_code, 200)
        self.assertIn('/media/profile_avatars/', uploaded.data['avatar_url'])
        contacts = self.client.get('/api/users')
        contact = next(item for item in contacts.data if item['id'] == user.id)
        self.assertEqual(contact['display_name'], 'Yangi Ism')
        self.assertIn('/media/profile_avatars/', contact['avatar_url'])

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
