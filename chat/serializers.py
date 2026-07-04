from django.contrib.auth import get_user_model
from rest_framework import serializers

from chat.models import Conversation, ConversationKeyEnvelope, ConversationParticipant, Message


User = get_user_model()


class PrivateConversationSerializer(serializers.Serializer):
    other_user_id = serializers.IntegerField()


class MessageCreateSerializer(serializers.Serializer):
    body = serializers.CharField(allow_blank=False, trim_whitespace=True)


class MessageSerializer(serializers.ModelSerializer):
    conversation_id = serializers.IntegerField(source='conversation.id')
    sender_id = serializers.IntegerField(source='sender.id')
    sender_name = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = [
            'id',
            'conversation_id',
            'sender_id',
            'sender_name',
            'body',
            'created_at',
        ]

    def get_sender_name(self, obj):
        return obj.sender.first_name or obj.sender.username


class ConversationKeyEnvelopeSerializer(serializers.ModelSerializer):
    target_device_id = serializers.CharField(source='target_device.device_id')
    sender_device_id = serializers.CharField(source='sender_device.device_id')

    class Meta:
        model = ConversationKeyEnvelope
        fields = [
            'key_id',
            'algorithm',
            'target_device_id',
            'sender_device_id',
            'wrapped_key',
            'created_at',
            'updated_at',
        ]


class ConversationKeyEnvelopeInputSerializer(serializers.Serializer):
    target_device_id = serializers.CharField()
    wrapped_key = serializers.CharField()


class ConversationKeyEnvelopeSyncSerializer(serializers.Serializer):
    key_id = serializers.CharField()
    algorithm = serializers.CharField()
    envelopes = ConversationKeyEnvelopeInputSerializer(many=True)


class ConversationSerializer(serializers.ModelSerializer):
    participant_ids = serializers.SerializerMethodField()
    last_message_preview = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = [
            'id',
            'type',
            'title',
            'participant_ids',
            'last_message_preview',
            'updated_at',
        ]

    def get_participant_ids(self, obj):
        return list(
            obj.participants.order_by('id').values_list('id', flat=True)
        )

    def get_last_message_preview(self, obj):
        message = getattr(obj, 'latest_message', None)
        if message is None:
            message = obj.messages.order_by('-created_at', '-id').first()
        if message is None:
            return ''
        return message.body


def get_or_create_private_conversation(user, other_user):
    existing = (
        Conversation.objects.filter(type=Conversation.ConversationType.PRIVATE)
        .filter(participants=user)
        .filter(participants=other_user)
    )

    for conversation in existing:
        participant_ids = set(
            ConversationParticipant.objects.filter(conversation=conversation)
            .values_list('user_id', flat=True)
        )
        if participant_ids == {user.id, other_user.id}:
            return conversation, False

    conversation = Conversation.objects.create(
        type=Conversation.ConversationType.PRIVATE,
        title='',
    )
    ConversationParticipant.objects.bulk_create(
        [
            ConversationParticipant(conversation=conversation, user=user),
            ConversationParticipant(conversation=conversation, user=other_user),
        ]
    )
    return conversation, True
