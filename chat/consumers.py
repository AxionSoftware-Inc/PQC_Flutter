import json
from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from channels.generic.websocket import AsyncWebsocketConsumer
from django.utils import timezone
from rest_framework.authtoken.models import Token

from users.models import WorkspaceMember


class ChatEventsConsumer(AsyncWebsocketConsumer):
    async def connect(self):
        params = parse_qs(self.scope['query_string'].decode('utf-8'))
        token_key = self._token_from_scope_headers()
        if not token_key:
            token_key = (params.get('token') or [''])[0].strip()
        requested_workspace_id = self._header_value('x-workspace-id')
        if not requested_workspace_id:
            requested_workspace_id = (params.get('workspace_id') or [''])[0].strip()
        self.device_id = self._header_value('x-device-id')
        if not self.device_id:
            self.device_id = (params.get('device_id') or [''])[0].strip()
        auth = await self._authenticate(token_key, requested_workspace_id)
        if auth is None:
            await self.close(code=4401)
            return
        self.user, self.workspace_id = auth
        self.workspace_group = f'workspace_{self.workspace_id}'
        await self.channel_layer.group_add(self.workspace_group, self.channel_name)
        await self.accept()
        await self._touch_device('online')
        await self._broadcast_presence('online')

    async def _broadcast_presence(self, state):
        await self.channel_layer.group_send(
            self.workspace_group,
            {
                'type': 'chat.event',
                'event': 'presence.changed',
                'payload': {
                    'workspace_id': self.workspace_id,
                    'user_id': self.user.id,
                    'state': state,
                    'device_id': self.device_id,
                    'last_seen_at': timezone.now().isoformat(),
                },
            },
        )

    async def disconnect(self, close_code):
        if hasattr(self, 'workspace_group'):
            await self._touch_device('offline')
            await self._broadcast_presence('offline')
            await self.channel_layer.group_discard(self.workspace_group, self.channel_name)

    @database_sync_to_async
    def _touch_device(self, state):
        if not getattr(self, 'device_id', ''):
            return
        from users.models import UserDevice

        UserDevice.objects.filter(
            user=self.user,
            device_id=self.device_id,
        ).update(
            status=UserDevice.Status.ACTIVE,
            last_seen_at=timezone.now(),
        )

    async def receive(self, text_data=None, bytes_data=None):
        if not text_data:
            return
        try:
            decoded = json.loads(text_data)
        except json.JSONDecodeError:
            return
        event = decoded.get('event', '')
        payload = decoded.get('payload', {})
        if event in {'typing.started', 'typing.stopped', 'receipt.delivered', 'receipt.read'}:
            if event.startswith('receipt.'):
                await self._save_receipt(event, payload)
            await self.channel_layer.group_send(
                self.workspace_group,
                {
                    'type': 'chat.event',
                    'event': event,
                    'payload': {
                        **payload,
                        'workspace_id': self.workspace_id,
                        'user_id': self.user.id,
                        'device_id': self.device_id,
                    },
                },
            )

    @database_sync_to_async
    def _save_receipt(self, event, payload):
        from chat.models import Message, MessageReceipt

        message_id = payload.get('message_id')
        if not isinstance(message_id, int):
            return
        message = Message.objects.filter(
            id=message_id,
            conversation__workspace_id=self.workspace_id,
            conversation__participants=self.user,
        ).first()
        if message is None or message.sender_id == self.user.id:
            return
        receipt, _ = MessageReceipt.objects.get_or_create(
            message=message,
            user=self.user,
        )
        now = timezone.now()
        if event == 'receipt.read':
            receipt.delivered_at = receipt.delivered_at or now
            receipt.read_at = now
        else:
            receipt.delivered_at = receipt.delivered_at or now
        receipt.save(update_fields=['delivered_at', 'read_at', 'updated_at'])

    async def chat_event(self, event):
        await self.send_json(
            {
                'event': event['event'],
                'payload': event['payload'],
            }
        )

    async def send_json(self, payload):
        await self.send(text_data=json.dumps(payload))

    def _header_value(self, name):
        for key, value in self.scope.get('headers', []):
            if key.decode('latin1').lower() == name:
                return value.decode('latin1').strip()
        return ''

    def _token_from_scope_headers(self):
        authorization = self._header_value('authorization')
        if authorization.lower().startswith('token '):
            return authorization[6:].strip()
        return ''

    @database_sync_to_async
    def _authenticate(self, token_key, requested_workspace_id):
        if not token_key:
            return None
        token = Token.objects.select_related('user').filter(key=token_key).first()
        if token is None:
            return None
        memberships = WorkspaceMember.objects.select_related('workspace').filter(
            organization_member__user=token.user,
            organization_member__is_active=True,
            is_active=True,
        )
        if requested_workspace_id.isdigit():
            membership = memberships.filter(workspace_id=int(requested_workspace_id)).first()
            if membership is not None:
                return token.user, membership.workspace_id
        membership = memberships.order_by('-workspace__is_default', 'workspace_id').first()
        if membership is None:
            return None
        return token.user, membership.workspace_id
