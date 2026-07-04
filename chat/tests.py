from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework.test import APITestCase

from chat.models import Conversation, ConversationKeyEnvelope, ConversationParticipant
from users.models import UserDevice


User = get_user_model()
VALID_PUBLIC_KEY_1 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='
VALID_PUBLIC_KEY_2 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE='


class ChatApiTests(APITestCase):
    def setUp(self):
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
        self.token = login.data['token']
        self.user = User.objects.get(username='ali')
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
        outsider = User.objects.get(username='laylo')
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
        other = User.objects.get(username='vali')

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
        response = self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': 'hello group'},
            format='json',
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.data['body'], 'hello group')

    def test_non_participant_cannot_post(self):
        self.client.post(
            '/api/auth/login',
            {'username': 'vali', 'device_id': 'device-2'},
            format='json',
        )
        other = User.objects.get(username='vali')
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
            {'body': 'first'},
            format='json',
        )
        self.client.post(
            f'/api/conversations/{self.group.id}/messages',
            {'body': 'second'},
            format='json',
        )

        response = self.client.get(f'/api/conversations/{self.group.id}/messages')

        self.assertEqual(response.status_code, 200)
        self.assertEqual([item['body'] for item in response.data][-2:], ['first', 'second'])

    def test_group_chat_handles_high_message_volume(self):
        total_messages = 180

        for index in range(total_messages):
            response = self.client.post(
                f'/api/conversations/{self.group.id}/messages',
                {'body': f'group-message-{index:03d}'},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        response = self.client.get(f'/api/conversations/{self.group.id}/messages')

        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data), total_messages)
        self.assertEqual(response.data[0]['body'], 'group-message-000')
        self.assertEqual(response.data[-1]['body'], 'group-message-179')

    def test_private_chat_handles_heavy_back_and_forth(self):
        other_client = APIClient()
        other_login = other_client.post(
            '/api/auth/login',
            {'username': 'laylo', 'device_id': 'device-4'},
            format='json',
        )
        self.assertEqual(other_login.status_code, 200)
        other_client.credentials(
            HTTP_AUTHORIZATION=f"Token {other_login.data['token']}",
        )
        other = User.objects.get(username='laylo')

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
                {'body': f'{sender}-message-{index:03d}'},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        ali_view = self.client.get(f'/api/conversations/{conversation_id}/messages')
        laylo_view = other_client.get(f'/api/conversations/{conversation_id}/messages')

        self.assertEqual(ali_view.status_code, 200)
        self.assertEqual(laylo_view.status_code, 200)
        self.assertEqual(len(ali_view.data), total_messages)
        self.assertEqual(len(laylo_view.data), total_messages)
        self.assertEqual(ali_view.data[0]['body'], 'ali-message-000')
        self.assertEqual(ali_view.data[-1]['body'], 'laylo-message-119')

    def test_repeated_polling_reads_remain_stable_after_many_messages(self):
        for index in range(90):
            response = self.client.post(
                f'/api/conversations/{self.group.id}/messages',
                {'body': f'poll-message-{index:03d}'},
                format='json',
            )
            self.assertEqual(response.status_code, 201)

        expected_tail = [f'poll-message-{index:03d}' for index in range(85, 90)]

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
            {'username': 'vali', 'device_id': 'device-2'},
            format='json',
        )
        other = User.objects.get(username='vali')
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
                {'body': f'group-burst-{index:03d}'},
                format='json',
            )
            private_response = self.client.post(
                f'/api/conversations/{private_id}/messages',
                {'body': f'private-burst-{index:03d}'},
                format='json',
            )
            self.assertEqual(group_response.status_code, 201)
            self.assertEqual(private_response.status_code, 201)

        response = self.client.get('/api/conversations')

        self.assertEqual(response.status_code, 200)
        self.assertGreaterEqual(len(response.data), 2)
        previews = {item['id']: item['last_message_preview'] for item in response.data}
        self.assertEqual(previews[self.group.id], 'group-burst-039')
        self.assertEqual(previews[private_id], 'private-burst-039')

    def test_group_key_envelopes_round_trip_for_registered_device(self):
        other_login = self.client.post(
            '/api/auth/login',
            {
                'username': 'vali',
                'device_id': 'device-2',
                'identity_public_key': VALID_PUBLIC_KEY_2,
                'key_algorithm': 'x25519',
            },
            format='json',
        )
        self.assertEqual(other_login.status_code, 200)

        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-x25519-aesgcm-v1',
                'envelopes': [
                    {
                        'target_device_id': 'device-1',
                        'wrapped_key': 'group-wrap:v1:nonce:cipher:mac',
                    },
                    {
                        'target_device_id': 'device-2',
                        'wrapped_key': 'group-wrap:v1:nonce2:cipher2:mac2',
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
            identity_public_key='outsider-public',
            key_algorithm='x25519',
        )

        response = self.client.post(
            f'/api/conversations/{self.group.id}/keys',
            {
                'key_id': 'group-key-1',
                'algorithm': 'group-x25519-aesgcm-v1',
                'envelopes': [
                    {
                        'target_device_id': outsider_device.device_id,
                        'wrapped_key': 'group-wrap:v1:nonce:cipher:mac',
                    },
                ],
            },
            format='json',
            HTTP_X_DEVICE_ID='device-1',
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn('is not part of this conversation', response.data['detail'])
