import hashlib
import logging
import os
import tempfile
import uuid
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Q
from django.http import Http404, HttpResponse
from django.utils import timezone
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import (
    AttachmentChunkReceipt,
    AttachmentUploadSession,
    Conversation,
    ConversationCryptoEpoch,
    Message,
    MessageReceipt,
    MessageReaction,
    MessageAttachment,
)
from chat.serializers import (
    AttachmentUploadSerializer,
    AttachmentSessionCompleteSerializer,
    AttachmentSessionCreateSerializer,
    AttachmentUploadSessionSerializer,
    ConversationSerializer,
    GROUP_ENVELOPE_ALGORITHM,
    ConversationKeyEnvelopeSerializer,
    ConversationKeyEnvelopeSyncSerializer,
    MessageCreateSerializer,
    MessageAttachmentSerializer,
    MessageSerializer,
    MessageReactionSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)
from chat.protocols import get_protocol_capabilities
from chat.protocols import v2 as v2_protocol
from users.models import UserDevice, WorkspaceMember
from users.serializers import (
    is_valid_ml_kem_768_public_key,
    normalize_supported_protocols,
)


User = get_user_model()
DEFAULT_ATTACHMENT_SESSION_TTL_DAYS = 7
logger = logging.getLogger(__name__)



from .common import (
    get_request_device_or_400,
    get_user_conversation_or_404,
    publish_workspace_event_on_commit,
)

class MessageListCreateView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        after_id = request.query_params.get('after_id', '').strip()
        before_id = request.query_params.get('before_id', '').strip()
        limit_value = request.query_params.get('limit', '').strip()
        try:
            limit = min(max(int(limit_value), 1), 100) if limit_value else None
        except (TypeError, ValueError):
            limit = 50
        messages_query = conversation.messages.select_related('sender').prefetch_related('attachments')
        if after_id.isdigit():
            messages = messages_query.filter(id__gt=int(after_id)).order_by('id')
            if limit is not None:
                messages = messages[:limit]
        elif before_id.isdigit():
            messages = messages_query.filter(id__lt=int(before_id)).order_by('-id')
            if limit is not None:
                messages = messages[:limit]
            messages = list(messages)
            messages.reverse()
        else:
            messages = messages_query.order_by('-id')
            if limit is not None:
                messages = messages[:limit]
            messages = list(messages)
            messages.reverse()
        return Response(
            MessageSerializer(
                messages,
                many=True,
                context={'request': request},
            ).data
        )

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        serializer = MessageCreateSerializer(
            data=request.data,
            context={'conversation': conversation},
        )
        serializer.is_valid(raise_exception=True)

        if not conversation.participants.filter(id=request.user.id).exists():
            raise PermissionDenied('Not a participant of this conversation.')

        client_message_id = serializer.validated_data['client_message_id'].strip()
        message_defaults = {
            'body': serializer.validated_data['body'].strip(),
            'message_type': serializer.validated_data['message_type'],
            'reply_to_id': serializer.validated_data.get('reply_to_id'),
        }
        if client_message_id:
            message, created = Message.objects.get_or_create(
                conversation=conversation,
                sender=request.user,
                client_message_id=client_message_id,
                defaults=message_defaults,
            )
            if not created:
                return Response(
                    MessageSerializer(message, context={'request': request}).data
                )
        else:
            message = Message.objects.create(
                conversation=conversation,
                sender=request.user,
                client_message_id='',
                **message_defaults,
            )
        attachments = MessageAttachment.objects.filter(
            id__in=serializer.validated_data['attachment_ids'],
            conversation=conversation,
            workspace=conversation.workspace,
            uploaded_by=request.user,
            message__isnull=True,
        )
        attachment_count = attachments.count()
        if attachment_count:
            attachments.update(message=message)
            message.attachment_count = attachment_count
            message.save(update_fields=['attachment_count'])
        conversation.save(update_fields=['updated_at'])
        serialized = MessageSerializer(message, context={'request': request}).data
        publish_workspace_event_on_commit(
            conversation.workspace_id,
            'message.created',
            serialized,
        )
        publish_workspace_event_on_commit(
            conversation.workspace_id,
            'conversation.updated',
            {
                'id': conversation.id,
                'workspace_id': conversation.workspace_id,
                'updated_at': conversation.updated_at.isoformat(),
            },
        )
        return Response(
            serialized,
            status=status.HTTP_201_CREATED,
        )


class MessageActionView(APIView):
    def _message(self, request, message_id):
        conversation = get_user_conversation_or_404(
            request,
            Message.objects.values_list('conversation_id', flat=True)
            .filter(id=message_id).first(),
        )
        return generics.get_object_or_404(
            Message.objects.select_related('conversation', 'sender'),
            id=message_id,
            conversation=conversation,
        )

    def patch(self, request, message_id):
        message = self._message(request, message_id)
        if message.sender_id != request.user.id:
            raise PermissionDenied('Only the sender can edit a message.')
        body = request.data.get('body')
        if not isinstance(body, str) or not body.strip():
            return Response({'detail': 'body is required.'}, status=status.HTTP_400_BAD_REQUEST)
        message.body = body.strip()
        message.edited_at = timezone.now()
        message.save(update_fields=['body', 'edited_at'])
        serialized = MessageSerializer(message, context={'request': request}).data
        publish_workspace_event_on_commit(message.conversation.workspace_id, 'message.updated', serialized)
        return Response(serialized)

    @transaction.atomic
    def post(self, request, message_id):
        source = self._message(request, message_id)
        target_id = request.data.get('conversation_id')
        if not isinstance(target_id, int):
            return Response({'detail': 'conversation_id is required.'}, status=status.HTTP_400_BAD_REQUEST)
        target = get_user_conversation_or_404(request, target_id)
        forwarded = Message.objects.create(
            conversation=target,
            sender=request.user,
            body=source.body,
            message_type=source.message_type,
            forwarded_from=source,
        )
        target.save(update_fields=['updated_at'])
        serialized = MessageSerializer(forwarded, context={'request': request}).data
        publish_workspace_event_on_commit(target.workspace_id, 'message.created', serialized)
        return Response(serialized, status=status.HTTP_201_CREATED)

    def delete(self, request, message_id):
        message = self._message(request, message_id)
        if message.sender_id != request.user.id:
            raise PermissionDenied('Only the sender can delete a message.')
        message.body = ''
        message.deleted_at = timezone.now()
        message.save(update_fields=['body', 'deleted_at'])
        serialized = MessageSerializer(message, context={'request': request}).data
        publish_workspace_event_on_commit(message.conversation.workspace_id, 'message.deleted', serialized)
        return Response(serialized)


class MessageReadView(APIView):
    """Persist a read receipt when websocket delivery is unavailable."""

    @transaction.atomic
    def post(self, request, message_id):
        message = generics.get_object_or_404(
            Message.objects.select_related('conversation', 'sender'),
            id=message_id,
        )
        get_user_conversation_or_404(request, message.conversation_id)
        if message.sender_id == request.user.id:
            return Response(
                MessageSerializer(message, context={'request': request}).data
            )
        now = timezone.now()
        receipt, _ = MessageReceipt.objects.get_or_create(
            message=message,
            user=request.user,
        )
        if receipt.read_at is None or receipt.delivered_at is None:
            receipt.delivered_at = receipt.delivered_at or now
            receipt.read_at = receipt.read_at or now
            receipt.save(update_fields=['delivered_at', 'read_at', 'updated_at'])
            publish_workspace_event_on_commit(
                message.conversation.workspace_id,
                'receipt.read',
                {
                    'conversation_id': message.conversation_id,
                    'message_id': message.id,
                    'user_id': request.user.id,
                    'read_at': receipt.read_at.isoformat(),
                },
            )
        return Response(
            MessageSerializer(message, context={'request': request}).data
        )


class MessageReactionView(APIView):
    def post(self, request, message_id):
        message = generics.get_object_or_404(Message, id=message_id)
        get_user_conversation_or_404(request, message.conversation_id)
        emoji = request.data.get('emoji', '')
        if not isinstance(emoji, str) or len(emoji.strip()) > 16 or not emoji.strip():
            return Response({'detail': 'A valid emoji is required.'}, status=status.HTTP_400_BAD_REQUEST)
        reaction, _ = MessageReaction.objects.update_or_create(
            message=message,
            user=request.user,
            defaults={'emoji': emoji.strip()},
        )
        payload = MessageReactionSerializer(reaction).data | {'message_id': message.id}
        publish_workspace_event_on_commit(message.conversation.workspace_id, 'reaction.updated', payload)
        return Response(payload)

    def delete(self, request, message_id):
        message = generics.get_object_or_404(Message, id=message_id)
        get_user_conversation_or_404(request, message.conversation_id)
        MessageReaction.objects.filter(message=message, user=request.user).delete()
        publish_workspace_event_on_commit(
            message.conversation.workspace_id,
            'reaction.deleted',
            {'message_id': message.id, 'user_id': request.user.id},
        )
        return Response(status=status.HTTP_204_NO_CONTENT)


class ConversationKeyEnvelopeView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        device, error_response = get_request_device_or_400(request)
        if error_response is not None:
            return error_response

        envelopes = conversation.key_envelopes.filter(
            target_device=device,
        ).select_related('target_device', 'sender_device')
        return Response(
            ConversationKeyEnvelopeSerializer(envelopes, many=True).data
        )

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        sender_device, error_response = get_request_device_or_400(request)
        if error_response is not None:
            return error_response

        serializer = ConversationKeyEnvelopeSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        submitted_envelopes = serializer.validated_data['envelopes']
        uses_v25_envelope = any(
            item['wrapped_key'].startswith(v2_protocol.GROUP_ENVELOPE_V25_PREFIX)
            for item in submitted_envelopes
        )

        participant_user_ids = set(
            conversation.participants.values_list('id', flat=True)
        )
        expected_target_devices = list(
            UserDevice.objects.filter(
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
                pqc_algorithm='ml-kem-768',
                pqc_signing_algorithm='ml-dsa-65',
            )
            .exclude(pqc_public_key='')
            .exclude(pqc_signing_public_key='')
        )
        expected_target_ids = {
            device.device_id
            for device in expected_target_devices
            if is_valid_ml_kem_768_public_key(device.pqc_public_key)
        }
        if uses_v25_envelope:
            unsupported_devices = [
                device.device_id
                for device in expected_target_devices
                if 'v2.5' not in normalize_supported_protocols(
                    device.supported_protocols
                )
            ]
            if unsupported_devices:
                return Response(
                    {
                        'detail': (
                            'V2.5 group envelopes cannot be stored for devices '
                            'without V2.5 capability.'
                        ),
                        'unsupported_devices': sorted(unsupported_devices),
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        submitted_target_ids = []
        for item in submitted_envelopes:
            submitted_target_ids.append(item['target_device_id'])
            target_device = UserDevice.objects.filter(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
            ).first()
            if target_device is None:
                return Response(
                    {
                        'detail': f"Target device '{item['target_device_id']}' is not part of this conversation.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        submitted_target_id_set = set(submitted_target_ids)

        if len(submitted_target_ids) != len(submitted_target_id_set):
            return Response(
                {'detail': 'Duplicate target_device_id entries are not allowed.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if expected_target_ids != submitted_target_id_set:
            missing_ids = sorted(expected_target_ids - submitted_target_id_set)
            extra_ids = sorted(submitted_target_id_set - expected_target_ids)
            parts = []
            if missing_ids:
                parts.append(f"missing devices: {', '.join(missing_ids)}")
            if extra_ids:
                parts.append(f"unexpected devices: {', '.join(extra_ids)}")
            return Response(
                {
                    'detail': 'Envelope set must exactly match the registered group devices.',
                    'mismatch': parts,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if serializer.validated_data['algorithm'] not in set(
            get_protocol_capabilities()['group_envelope_algorithms'].values()
        ):
            return Response(
                {
                    'detail': 'The group-key envelope algorithm is not enabled on this server.',
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        saved = []
        for item in serializer.validated_data['envelopes']:
            target_device = UserDevice.objects.get(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
            )
            envelope, _ = conversation.key_envelopes.update_or_create(
                target_device=target_device,
                key_id=serializer.validated_data['key_id'],
                defaults={
                    'sender_device': sender_device,
                    'algorithm': serializer.validated_data['algorithm'],
                    'wrapped_key': item['wrapped_key'],
                },
            )
            saved.append(envelope)

        ConversationCryptoEpoch.objects.filter(
            conversation=conversation,
            state__in=[
                ConversationCryptoEpoch.State.ACTIVE,
                ConversationCryptoEpoch.State.PENDING,
            ],
        ).exclude(epoch_id=serializer.validated_data['key_id']).update(
            state=ConversationCryptoEpoch.State.CLOSED,
        )
        ConversationCryptoEpoch.objects.update_or_create(
            conversation=conversation,
            epoch_id=serializer.validated_data['key_id'],
            defaults={
                'state': ConversationCryptoEpoch.State.ACTIVE,
                'reason': '',
                'activated_at': timezone.now(),
            },
        )

        return Response(
            ConversationKeyEnvelopeSerializer(saved, many=True).data,
            status=status.HTTP_201_CREATED,
        )


