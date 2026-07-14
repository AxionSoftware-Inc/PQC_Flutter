import base64
import hashlib
import os
from unittest.mock import patch

from django.test import SimpleTestCase, override_settings
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework.test import APITestCase

from chat.models import (
    AttachmentUploadSession,
    Conversation,
    ConversationKeyEnvelope,
    ConversationParticipant,
    MessageAttachment,
)
from users.models import UserDevice


User = get_user_model()
VALID_PUBLIC_KEY_1 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
VALID_PUBLIC_KEY_2 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='
VALID_PQC_PUBLIC_KEY_1 = base64.b64encode(bytes(1184)).decode()
VALID_PQC_PUBLIC_KEY_2 = base64.b64encode(bytes([1]) * 1184).decode()
VALID_PQC_SIGNING_PUBLIC_KEY_1 = base64.b64encode(bytes(1952)).decode()
VALID_PQC_SIGNING_PUBLIC_KEY_2 = base64.b64encode(bytes([1]) * 1952).decode()


class CryptoProtocolContractTests(SimpleTestCase):
    def test_capabilities_match_current_writers(self):
        response = self.client.get('/api/crypto/protocols')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['private_message_prefixes'], ['pqc:v2:'])
        self.assertEqual(response.data['group_message_prefixes'], ['group:v2:'])
        self.assertEqual(response.data['protocol_version'], 2)
        self.assertEqual(response.data['attachment_cipher_versions'], ['attachment:v2'])
        self.assertEqual(response.data['backup_schema_revision'], 2)

    def test_v3_test_mode_advertises_dual_read_and_v3_write(self):
        with patch.dict(os.environ, {'CRYPTO_PROTOCOL_MODE': 'v3_test'}):
            response = self.client.get('/api/crypto/protocols')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['active_writer'], 'v3')
        self.assertEqual(
            response.data['readable_private_message_prefixes'],
            ['pqc:v2:', 'pqc:v3:'],
        )
        self.assertEqual(response.data['private_message_prefixes'], ['pqc:v2:', 'pqc:v3:'])
        self.assertEqual(response.data['backup_schema_revision'], 3)


class ChatApiTests(APITestCase):
    def setUp(self):
        login = self.client.post(
            '/api/auth/login',
            {
                'username': 'ali',
                'device_id': 'device-1',
                'identity_public_key': VALID_PUBLIC_KEY_1,
                'key_algorithm': 'x25519',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_1,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_1,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        self.token = login.data['token']
        self.user = User.objects.get(id=login.data['account_id'])
        self.client.credentials(HTTP_AUTHORIZATION=f'Token {self.token}')
        self.group = Conversation.objects.get(
            type=Conversation.ConversationType.GROUP,
            title='General Group',
        )

    def test_user_only_sees_owned_conversations(self):
        outsider_login = self.client.post(
            '/api/auth/login',
            {'username': 'laylo', 'device_id': 'device-4'},
            format='json',
        )
        self.assertEqual(outsider_login.status_code, 200)
        outsider = User.objects.get(id=outsider_login.data['account_id'])
        hidden = Conversation.objects.create(
            type=Conversation.ConversationType.PRIVATE,
            title='',
        )
        ConversationParticipant.objects.create(conversation=hidden, user=outsider)

        response = self.client.get('/api/conversations')

        self.assertEqual(response.status_code, 200)
        ids = {item['id'] for item in response.data}
        self.assertIn(self.group.id, ids)
        self.assertNotIn(hidden.id, ids)

    def test_private_conversation_endpoint_reuses_existing_conversation(self):
        self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-2'},
            format='json',
        )
        other = User.objects.get(devices__device_id='device-2')

        first = self.client.post(
            '/api/private-conversations',
            {'other_user_id': other.id},
            format='json',
        )
        second = self.client.post(
            '/api/private-conversations',
            {'other_user_id': other.id},
            format='json',
        )

        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.data['id'], second.data['id'])

    def test_group_chat_accepts_messages(self):
        payload = _group_payload('hello-group')
        response = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': payload},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['body'], payload)

    def test_group_chat_rejects_plaintext_messages(self):
        response = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': 'hello group'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('group:v2', str(response.data))

    def test_non_participant_cannot_post(self):
        self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-2'},
            format='json',
        )
        other = User.objects.get(devices__device_id='device-2')
        hidden = Conversation.objects.create(
            type=Conversation.ConversationType.PRIVATE,
            title='',
        )
        ConversationParticipant.objects.create(conversation=hidden, user=other)

        response = self.client.post(
            f'/api/conversations/{hidden.id}/messages',
            {'body': 'blocked'},
            format='json',
        )

        self.assertEqual(response.status_code, 404)

    def test_messages_are_returned_in_created_order(self):
        self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('first')},
            format='json',
        )
        self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('second')},
            format='json',
        )

        response = self.client.get(f'/api/conversations/{self.group.id}/messages')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            [item['body'] for item in response.data][-2:],
            [_group_payload('first'), _group_payload('second')],
        )

    def test_message_create_is_idempotent_for_client_message_id(self):
        first = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('once'), 'client_message_id': 'msg-1'},
            format='json',
        )
        second = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('once'), 'client_message_id': 'msg-1'},
            format='json',
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(first.data['id'], second.data['id'])

    def test_messages_support_incremental_after_id_sync(self):
        self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('first')},
            format='json',
        )
        second = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('second')},
            format='json',
        )

        response = self.client.get(
            f'/api/conversations/{self.group.id}/messages',
            {'after_id': second.data['id'] - 1},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['body'], _group_payload('second'))

    def test_conversations_support_incremental_updated_after_sync(self):
        first = self.client.get('/api/conversations')
        self.assertEqual(first.status_code, 200)

        self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': _group_payload('updated')},
            format='json',
        )

        response = self.client.get(
            '/api/conversations',
            {'updated_after': first.data[0]['updated_at']},
        )

        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['id'], self.group.id)

    def test_group_chat_handles_high_message_volume(self):
        total_messages = 180

        for index in range(total_messages):
            response = self.client.post(
                f'/api/conversations/{self.group.id}/messages',
                {'body': _group_payload(f'group-message-{index:03d}')},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        response = self.client.get(f'/api/conversations/{self.group.id}/messages')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), total_messages)
        self.assertEqual(response.data[0]['body'], _group_payload('group-message-000'))
        self.assertEqual(response.data[-1]['body'], _group_payload('group-message-179'))

    def test_private_chat_handles_heavy_back_and_forth(self):
        other_client = APIClient()
        other_login = other_client.post(
            '/api/auth/login',
            {
                'username': 'laylo',
                'device_id': 'device-4',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_2,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_2,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        self.assertEqual(other_login.status_code, 200)
        other_client.credentials(
            HTTP_AUTHORIZATION=f"Token {other_login.data['token']}",
        )
        other = User.objects.get(id=other_login.data['account_id'])

        conversation_response = self.client.post(
            '/api/private-conversations',
            {'other_user_id': other.id},
            format='json',
        )
        self.assertEqual(conversation_response.status_code, 200)
        conversation_id = conversation_response.data['id']

        total_messages = 120
        for index in range(total_messages):
            client = self.client if index % 2 == 0 else other_client
            sender = 'ali' if index % 2 == 0 else 'laylo'
            response = client.post(
                f'/api/conversations/{conversation_id}/messages',
                {'body': _private_payload(f'{sender}-message-{index:03d}')},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        ali_view = self.client.get(f'/api/conversations/{conversation_id}/messages')
        laylo_view = other_client.get(f'/api/conversations/{conversation_id}/messages')

        self.assertEqual(ali_view.status_code, 200)
        self.assertEqual(laylo_view.status_code, 200)
        self.assertEqual(len(ali_view.data), total_messages)
        self.assertEqual(len(laylo_view.data), total_messages)
        self.assertEqual(ali_view.data[0]['body'], _private_payload('ali-message-000'))
        self.assertEqual(
            ali_view.data[-1]['body'],
            _private_payload('laylo-message-119'),
        )

    def test_private_chat_rejects_plaintext_messages(self):
        self.client.post(
            '/api/auth/login',
            {
                'username': 'vali',
                'device_id': 'device-2',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_2,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_2,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        other = User.objects.get(devices__device_id='device-2')
        private_chat = self.client.post(
            '/api/private-conversations',
            {'other_user_id': other.id},
            format='json',
        )
        response = self.client.post(
            f"/api/conversations/{private_chat.data['id']}/messages",
            {'body': 'plaintext-private'},
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('pqc:v2', str(response.data))

    def test_repeated_polling_reads_remain_stable_after_many_messages(self):
        for index in range(90):
            response = self.client.post(
                f'/api/conversations/{self.group.id}/messages',
                {'body': _group_payload(f'poll-message-{index:03d}')},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        expected_tail = [
            _group_payload(f'poll-message-{index:03d}')
            for index in range(85, 90)
        ]

        for _ in range(15):
            response = self.client.get(f'/api/conversations/{self.group.id}/messages')
            self.assertEqual(response.status_code, 200)
            self.assertEqual(len(response.data), 90)
            self.assertEqual(
                [item['body'] for item in response.data[-5:]],
                expected_tail,
            )

    def test_conversation_list_stays_consistent_after_chat_load(self):
        self.client.post(
            '/api/auth/login',
            {
                'username': 'vali',
                'device_id': 'device-2',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_2,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_2,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        other = User.objects.get(devices__device_id='device-2')
        private_chat = self.client.post(
            '/api/private-conversations',
            {'other_user_id': other.id},
            format='json',
        )
        self.assertEqual(private_chat.status_code, 200)
        private_id = private_chat.data['id']

        for index in range(40):
            group_response = self.client.post(
                f'/api/conversations/{self.group.id}/messages',
                {'body': _group_payload(f'group-burst-{index:03d}')},
                format='json',
            )
            private_response = self.client.post(
                f'/api/conversations/{private_id}/messages',
                {'body': _private_payload(f'private-burst-{index:03d}')},
                format='json',
            )
            self.assertEqual(group_response.status_code, 201)
            self.assertEqual(private_response.status_code, 201)

        response = self.client.get('/api/conversations')

        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(len(response.data), 2)
        previews = {item['id']: item['last_message_preview'] for item in response.data}
        self.assertEqual(previews[self.group.id], _group_payload('group-burst-039'))
        self.assertEqual(previews[private_id], _private_payload('private-burst-039'))

    def test_group_key_envelopes_round_trip_for_registered_device(self):
        other_login = self.client.post(
            '/api/auth/login',
            {
                'username': 'vali',
                'device_id': 'device-2',
                'identity_public_key': VALID_PUBLIC_KEY_2,
                'key_algorithm': 'x25519',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_2,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_2,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        self.assertEqual(other_login.status_code, 200)

        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-ml-kem-768-aesgcm-v2',
                'envelopes': [
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem:nonce:cipher:mac:signature',
                    },
                    {
                        'target_device_id': 'device-2',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem2:nonce2:cipher2:mac2:signature2',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(
            ConversationKeyEnvelope.objects.filter(
                conversation=self.group,
                key_id='group-key-1',
            ).count(),
            2,
        )

        own_view = self.client.get(
            f'/api/conversations/{self.group.id}/keys',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(own_view.status_code, 200)
        self.assertEqual(len(own_view.data), 1)
        self.assertEqual(own_view.data[0]['target_device_id'], 'device-1')
        self.assertEqual(own_view.data[0]['sender_device_id'], 'device-1')

    def test_group_key_envelopes_require_registered_device_header(self):
        response = self.client.get(f'/api/conversations/{self.group.id}/keys')

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'X-Device-Id header is required.',
        )

    def test_group_key_envelope_rejects_foreign_target_device(self):
        outsider = User.objects.create_user(username='outsider')
        outsider_device = UserDevice.objects.create(
            user=outsider,
            device_id='outsider-device',
            pqc_public_key=VALID_PQC_PUBLIC_KEY_2,
            pqc_algorithm='ml-kem-768',
            pqc_signing_public_key=VALID_PQC_SIGNING_PUBLIC_KEY_2,
            pqc_signing_algorithm='ml-dsa-65',
        )

        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-ml-kem-768-aesgcm-v2',
                'envelopes': [
                    {
                        'target_device_id': outsider_device.device_id,
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem:nonce:cipher:mac:signature',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('is not part of this conversation', response.data['detail'])

    def test_group_key_envelope_rejects_partial_device_coverage(self):
        other_login = self.client.post(
            '/api/auth/login',
            {
                'username': 'vali',
                'device_id': 'device-2',
                'pqc_public_key': VALID_PQC_PUBLIC_KEY_2,
                'pqc_algorithm': 'ml-kem-768',
                'pqc_signing_public_key': VALID_PQC_SIGNING_PUBLIC_KEY_2,
                'pqc_signing_algorithm': 'ml-dsa-65',
            },
            format='json',
        )
        self.assertEqual(other_login.status_code, 200)

        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-ml-kem-768-aesgcm-v2',
                'envelopes': [
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem:nonce:cipher:mac:signature',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'Envelope set must exactly match the registered group devices.',
        )
        self.assertIn('missing devices: device-2', response.data['mismatch'][0])

    def test_group_key_envelope_rejects_duplicate_target_devices(self):
        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-ml-kem-768-aesgcm-v2',
                'envelopes': [
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem:nonce:cipher:mac:signature',
                    },
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem2:nonce2:cipher2:mac2:signature2',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.data['detail'],
            'Duplicate target_device_id entries are not allowed.',
        )

    def test_group_key_envelope_rejects_legacy_algorithm(self):
        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-x25519-aesgcm-v1',
                'envelopes': [
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:pqc:v2:device-1:sign:kem:nonce:cipher:mac:signature',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('group-ml-kem-768-aesgcm-v2', str(response.data))

    def test_attachment_session_upload_complete_and_chunk_download(self):
        create = self.client.post(
            f'/api/conversations/{self.group.id}/attachment-sessions',
            {
                'filename': 'report.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 17,
                'ciphertext_size': 65,
                'chunk_size': 8,
                'total_chunks': 3,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('file-wrap'),
            },
            format='json',
        )

        self.assertEqual(create.status_code, 201)
        session_id = create.data['session_id']

        chunks = [b'A' * 24, b'B' * 24, b'C' * 17]
        for index, chunk in enumerate(chunks):
            response = self.client.generic(
                'PUT',
                f'/api/attachment-sessions/{session_id}/chunks/{index}',
                chunk,
                content_type='application/octet-stream',
                HTTP_X_CHUNK_SHA256=hashlib.sha256(chunk).hexdigest(),
                HTTP_X_CHUNK_SIZE=str(len(chunk)),
            )
            self.assertEqual(response.status_code, 201)

        detail = self.client.get(f'/api/attachment-sessions/{session_id}')
        self.assertEqual(detail.status_code, 200)
        self.assertEqual(detail.data['completed_chunks'], 3)
        self.assertEqual(detail.data['received_chunks'], [0, 1, 2])

        complete = self.client.post(
            f'/api/attachment-sessions/{session_id}/complete',
            {'manifest_sha256': 'manifest-sha'},
            format='json',
        )
        self.assertEqual(complete.status_code, 201)
        attachment_id = complete.data['id']

        attachment = MessageAttachment.objects.get(id=attachment_id)
        self.assertEqual(attachment.cipher_version, 'attachment:v1')
        self.assertEqual(attachment.file_key_wrap, _private_payload('file-wrap'))

        descriptor = self.client.get(f'/api/attachments/{attachment_id}/download')
        self.assertEqual(descriptor.status_code, 200)
        self.assertEqual(descriptor.data['download']['total_chunks'], 3)

        chunk = self.client.get(f'/api/attachments/{attachment_id}/chunks/1')
        self.assertEqual(chunk.status_code, 200)
        self.assertEqual(chunk.content, chunks[1])

    def test_attachment_session_chunk_upload_is_idempotent(self):
        create = self.client.post(
            f'/api/conversations/{self.group.id}/attachment-sessions',
            {
                'filename': 'dup.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 8,
                'ciphertext_size': 8,
                'chunk_size': 8,
                'total_chunks': 1,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('dup-wrap'),
            },
            format='json',
        )
        session_id = create.data['session_id']
        chunk_bytes = b'abcdefgh'
        checksum = hashlib.sha256(chunk_bytes).hexdigest()

        first = self.client.generic(
            'PUT',
            f'/api/attachment-sessions/{session_id}/chunks/0',
            chunk_bytes,
            content_type='application/octet-stream',
            HTTP_X_CHUNK_SHA256=checksum,
            HTTP_X_CHUNK_SIZE=str(len(chunk_bytes)),
        )
        second = self.client.generic(
            'PUT',
            f'/api/attachment-sessions/{session_id}/chunks/0',
            chunk_bytes,
            content_type='application/octet-stream',
            HTTP_X_CHUNK_SHA256=checksum,
            HTTP_X_CHUNK_SIZE=str(len(chunk_bytes)),
        )

        self.assertEqual(first.status_code, 201)
        self.assertEqual(second.status_code, 200)
        self.assertTrue(second.data['duplicate'])
        self.assertEqual(
            AttachmentUploadSession.objects.get(session_id=session_id).chunk_receipts.count(),
            1,
        )

    @override_settings(ATTACHMENTS_MAX_FILE_BYTES=16)
    def test_attachment_session_create_rejects_when_file_exceeds_limit(self):
        response = self.client.post(
            f'/api/conversations/{self.group.id}/attachment-sessions',
            {
                'filename': 'too-large.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 17,
                'ciphertext_size': 33,
                'chunk_size': 8,
                'total_chunks': 3,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('too-large-wrap'),
            },
            format='json',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('configured file limit', str(response.data))

    def test_attachment_session_complete_rejects_missing_chunks(self):
        create = self.client.post(
            f'/api/conversations/{self.group.id}/attachment-sessions',
            {
                'filename': 'incomplete.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 20,
                'ciphertext_size': 20,
                'chunk_size': 10,
                'total_chunks': 2,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('incomplete-wrap'),
            },
            format='json',
        )
        session_id = create.data['session_id']
        chunk_bytes = b'0123456789'
        response = self.client.generic(
            'PUT',
            f'/api/attachment-sessions/{session_id}/chunks/0',
            chunk_bytes,
            content_type='application/octet-stream',
            HTTP_X_CHUNK_SHA256=hashlib.sha256(chunk_bytes).hexdigest(),
            HTTP_X_CHUNK_SIZE=str(len(chunk_bytes)),
        )
        self.assertEqual(response.status_code, 201)

        complete = self.client.post(
            f'/api/attachment-sessions/{session_id}/complete',
            {'manifest_sha256': 'manifest-sha'},
            format='json',
        )
        self.assertEqual(complete.status_code, 400)
        self.assertIn('Missing chunks', complete.data['detail'])

    def test_attachment_chunk_upload_rejects_wrong_checksum(self):
        create = self.client.post(
            f'/api/conversations/{self.group.id}/attachment-sessions',
            {
                'filename': 'checksum.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 4,
                'ciphertext_size': 4,
                'chunk_size': 4,
                'total_chunks': 1,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('checksum-wrap'),
            },
            format='json',
        )
        session_id = create.data['session_id']

        response = self.client.generic(
            'PUT',
            f'/api/attachment-sessions/{session_id}/chunks/0',
            b'data',
            content_type='application/octet-stream',
            HTTP_X_CHUNK_SHA256='deadbeef',
            HTTP_X_CHUNK_SIZE='4',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('checksum mismatch', response.data['detail'])

    def test_attachment_download_requires_membership(self):
        hidden = Conversation.objects.create(
            type=Conversation.ConversationType.PRIVATE,
            title='private-attachment-room',
            workspace=self.group.workspace,
        )
        ConversationParticipant.objects.create(conversation=hidden, user=self.user)
        create = self.client.post(
            f'/api/conversations/{hidden.id}/attachment-sessions',
            {
                'filename': 'private.bin',
                'mime_type': 'application/octet-stream',
                'cipher_version': 'attachment:v1',
                'plaintext_size': 9,
                'ciphertext_size': 25,
                'chunk_size': 9,
                'total_chunks': 1,
                'plaintext_sha256': 'plain-sha',
                'manifest_sha256': 'manifest-sha',
                'file_key_wrap': _private_payload('private-wrap'),
            },
            format='json',
        )
        session_id = create.data['session_id']
        chunk_bytes = b'locked123' + (b'!' * 16)
        self.client.generic(
            'PUT',
            f'/api/attachment-sessions/{session_id}/chunks/0',
            chunk_bytes,
            content_type='application/octet-stream',
            HTTP_X_CHUNK_SHA256=hashlib.sha256(chunk_bytes).hexdigest(),
            HTTP_X_CHUNK_SIZE=str(len(chunk_bytes)),
        )
        complete = self.client.post(
            f'/api/attachment-sessions/{session_id}/complete',
            {'manifest_sha256': 'manifest-sha'},
            format='json',
        )
        attachment_id = complete.data['id']

        outsider_client = APIClient()
        outsider_login = outsider_client.post(
            '/api/auth/login',
            {'username': 'outsider', 'device_id': 'device-9'},
            format='json',
        )
        self.assertEqual(outsider_login.status_code, 200)
        outsider_client.credentials(
            HTTP_AUTHORIZATION=f"Token {outsider_login.data['token']}",
        )

        response = outsider_client.get(f'/api/attachments/{attachment_id}/download')
        self.assertEqual(response.status_code, 404)


def _group_payload(label):
    return f'group:v2:key-{label}:nonce-{label}:cipher-{label}:mac-{label}'


def _private_payload(label):
    return (
        f'pqc:v2:sender:{label}-sign:target:{label}-selfkem:{label}-selfnonce:'
        f'{label}-selfcipher:{label}-selfmac:{label}-peerkem:{label}-peernonce:'
        f'{label}-peercipher:{label}-peermac:{label}-contentnonce:'
        f'{label}-contentcipher:{label}-contentmac:{label}-signature'
    )
