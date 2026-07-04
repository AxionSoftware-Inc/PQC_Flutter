from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, Message
from chat.serializers import (
    ConversationSerializer,
    ConversationKeyEnvelopeSerializer,
    ConversationKeyEnvelopeSyncSerializer,
    MessageCreateSerializer,
    MessageSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)
from users.models import UserDevice


User = get_user_model()


def get_user_conversation_or_404(user, conversation_id):
    return generics.get_object_or_404(
        Conversation.objects.filter(participants=user).distinct(),
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


class ConversationListView(APIView):
    def get(self, request):
        conversations = (
            Conversation.objects.filter(participants=request.user)
            .prefetch_related('participants', 'messages')
            .distinct()
        )
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

        conversation, _ = get_or_create_private_conversation(
            request.user,
            other_user,
        )
        return Response(ConversationSerializer(conversation).data)


class MessageListCreateView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request.user, conversation_id)
        messages = conversation.messages.select_related('sender').all()
        return Response(MessageSerializer(messages, many=True).data)

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request.user, conversation_id)
        serializer = MessageCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        if not conversation.participants.filter(id=request.user.id).exists():
            raise PermissionDenied('Not a participant of this conversation.')

        message = Message.objects.create(
            conversation=conversation,
            sender=request.user,
            body=serializer.validated_data['body'].strip(),
        )
        conversation.save(update_fields=['updated_at'])
        return Response(
            MessageSerializer(message).data,
            status=status.HTTP_201_CREATED,
        )


class ConversationKeyEnvelopeView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request.user, conversation_id)
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
        conversation = get_user_conversation_or_404(request.user, conversation_id)
        if conversation.type != Conversation.ConversationType.GROUP:
            return Response(
                {'detail': 'Conversation key envelopes are only used for group chats.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        sender_device, error_response = get_request_device_or_400(request)
        if error_response is not None:
            return error_response

        serializer = ConversationKeyEnvelopeSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        participant_user_ids = set(
            conversation.participants.values_list('id', flat=True)
        )
        saved = []
        for item in serializer.validated_data['envelopes']:
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
