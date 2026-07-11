from django.contrib.auth import get_user_model
from django.core.files.storage import default_storage
from django.db import transaction
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, Message, MessageAttachment
from chat.serializers import (
    AttachmentUploadSerializer,
    ConversationSerializer,
    GROUP_ENVELOPE_ALGORITHM,
    ConversationKeyEnvelopeSerializer,
    ConversationKeyEnvelopeSyncSerializer,
    MessageCreateSerializer,
    MessageAttachmentSerializer,
    MessageSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)
from users.models import UserDevice, WorkspaceMember


User = get_user_model()


def get_user_conversation_or_404(request, conversation_id):
    workspace, error_response = get_request_workspace_or_403(request)
    if error_response is not None:
        raise PermissionDenied(error_response.data['detail'])
    return generics.get_object_or_404(
        Conversation.objects.filter(
            participants=request.user,
            workspace=workspace,
            workspace__members__organization_member__user=request.user,
            workspace__members__organization_member__is_active=True,
            workspace__members__is_active=True,
        ).distinct(),
        pk=conversation_id,
    )


def get_request_device_or_400(request):
    device_id = request.headers.get('X-Device-Id', '').strip()
    if not device_id:
        return None, Response(
            {'detail': 'X-Device-Id header is required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    device = UserDevice.objects.filter(
        user=request.user,
        device_id=device_id,
    ).first()
    if device is None:
        return None, Response(
            {'detail': 'Current device is not registered for this user.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    return device, None


def get_request_workspace_or_403(request):
    workspace_id = request.headers.get('X-Workspace-Id', '').strip()
    memberships = WorkspaceMember.objects.select_related(
        'workspace',
        'organization_member',
    ).filter(
        organization_member__user=request.user,
        organization_member__is_active=True,
        is_active=True,
    )
    if workspace_id.isdigit():
        membership = memberships.filter(workspace_id=int(workspace_id)).first()
        if membership is not None:
            return membership.workspace, None
    membership = memberships.order_by('-workspace__is_default', 'workspace_id').first()
    if membership is None:
        return None, Response(
            {'detail': 'No active workspace available.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return membership.workspace, None


def publish_workspace_event(workspace_id, event_type, payload):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f'workspace_{workspace_id}',
        {
            'type': 'chat.event',
            'event': event_type,
            'payload': payload,
        },
    )


class ConversationListView(APIView):
    def get(self, request):
        updated_after = request.query_params.get('updated_after', '').strip()
        workspace, error_response = get_request_workspace_or_403(request)
        if error_response is not None:
            return error_response
        conversations = (
            Conversation.objects.filter(
                participants=request.user,
                workspace=workspace,
            )
            .prefetch_related('participants', 'messages')
            .distinct()
        )
        if updated_after:
            conversations = conversations.filter(updated_at__gt=updated_after)
        return Response(ConversationSerializer(conversations, many=True).data)


class PrivateConversationView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = PrivateConversationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        other_user = generics.get_object_or_404(
            User,
            pk=serializer.validated_data['other_user_id'],
        )
        if other_user == request.user:
            return Response(
                {'detail': 'Cannot create private chat with yourself.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        workspace, error_response = get_request_workspace_or_403(request)
        if error_response is not None:
            return error_response

        conversation, _ = get_or_create_private_conversation(
            request.user,
            other_user,
            workspace,
        )
        return Response(ConversationSerializer(conversation).data)


class MessageListCreateView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        after_id = request.query_params.get('after_id', '').strip()
        messages = conversation.messages.select_related('sender').prefetch_related('attachments').all()
        if after_id.isdigit():
            messages = messages.filter(id__gt=int(after_id))
        return Response(MessageSerializer(messages, many=True).data)

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
        if client_message_id:
            existing = Message.objects.filter(
                conversation=conversation,
                sender=request.user,
                client_message_id=client_message_id,
            ).select_related('sender').first()
            if existing is not None:
                return Response(MessageSerializer(existing).data)

        message = Message.objects.create(
            conversation=conversation,
            sender=request.user,
            body=serializer.validated_data['body'].strip(),
            client_message_id=client_message_id,
            message_type=serializer.validated_data['message_type'],
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
        serialized = MessageSerializer(message).data
        publish_workspace_event(
            conversation.workspace_id,
            'message.created',
            serialized,
        )
        publish_workspace_event(
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

        participant_user_ids = set(
            conversation.participants.values_list('id', flat=True)
        )
        expected_target_ids = set(
            UserDevice.objects.filter(
                user_id__in=participant_user_ids,
                pqc_algorithm='ml-kem-768',
                pqc_signing_algorithm='ml-dsa-65',
            )
            .exclude(pqc_public_key='')
            .exclude(pqc_signing_public_key='')
            .values_list('device_id', flat=True)
        )
        submitted_target_ids = []
        for item in serializer.validated_data['envelopes']:
            submitted_target_ids.append(item['target_device_id'])
            target_device = UserDevice.objects.filter(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
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

        if serializer.validated_data['algorithm'] != GROUP_ENVELOPE_ALGORITHM:
            return Response(
                {
                    'detail': 'Only group-ml-kem-768-aesgcm-v1 is accepted.',
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        saved = []
        for item in serializer.validated_data['envelopes']:
            target_device = UserDevice.objects.get(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
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

        return Response(
            ConversationKeyEnvelopeSerializer(saved, many=True).data,
            status=status.HTTP_201_CREATED,
        )


class AttachmentUploadView(APIView):
    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        serializer = AttachmentUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        uploaded = serializer.validated_data['file']
        storage_key = default_storage.save(
            f'attachments/{conversation.workspace_id}/{conversation.id}/{uploaded.name}',
            uploaded,
        )
        attachment = MessageAttachment.objects.create(
            conversation=conversation,
            workspace=conversation.workspace,
            uploaded_by=request.user,
            filename=uploaded.name,
            mime_type=getattr(uploaded, 'content_type', 'application/octet-stream'),
            size_bytes=uploaded.size,
            storage_key=storage_key,
        )
        return Response(
            MessageAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )
