from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework import serializers

from chat.models import (
    AttachmentChunkReceipt,
    AttachmentUploadSession,
    Conversation,
    ConversationKeyEnvelope,
    ConversationParticipant,
    Message,
    MessageAttachment,
    ConversationCryptoEpoch,
)


User = get_user_model()
PRIVATE_MESSAGE_PREFIX = ('pqc:v2:',)
GROUP_MESSAGE_PREFIX = ('group:v2:',)
GROUP_ENVELOPE_PREFIX = 'group-wrap:pqc:v2:'
GROUP_ENVELOPE_ALGORITHM = 'group-ml-kem-768-aesgcm-v2'

# This is a public wire-protocol contract.  Existing payload readers stay in
# clients, while this list tells clients which current writers this deployment
# can accept.  A client must check it before encrypting a new outgoing message.
CRYPTO_PROTOCOL_CAPABILITIES = {
    'protocol_version': 2,
    'private_message_prefixes': list(PRIVATE_MESSAGE_PREFIX),
    'group_message_prefixes': list(GROUP_MESSAGE_PREFIX),
    'attachment_cipher_versions': ['attachment:v2'],
    'backup_schema_revision': 2,
}


class PrivateConversationSerializer(serializers.Serializer):
    other_user_id = serializers.IntegerField()


class MessageCreateSerializer(serializers.Serializer):
    body = serializers.CharField(allow_blank=True, trim_whitespace=True, default='')
    client_message_id = serializers.CharField(
        required=False,
        allow_blank=True,
        default='',
    )
    message_type = serializers.ChoiceField(
        choices=Message.MessageType.choices,
        default=Message.MessageType.TEXT,
    )
    attachment_ids = serializers.ListField(
        child=serializers.IntegerField(),
        required=False,
        default=list,
    )

    def validate(self, attrs):
        body = attrs.get('body', '').strip()
        attachment_ids = attrs.get('attachment_ids') or []
        if not body and not attachment_ids:
            raise serializers.ValidationError(
                'body or attachment_ids must be provided.'
            )
        conversation = self.context.get('conversation')
        if conversation is None or not body:
            return attrs
        if conversation.type == Conversation.ConversationType.PRIVATE:
            if not body.startswith(PRIVATE_MESSAGE_PREFIX):
                raise serializers.ValidationError(
                    {'body': 'Private chat messages must use pqc:v2 payloads.'}
                )
            return attrs
        if conversation.type == Conversation.ConversationType.GROUP:
            if ConversationCryptoEpoch.objects.filter(
                conversation=conversation,
                state=ConversationCryptoEpoch.State.PENDING,
            ).exists():
                raise serializers.ValidationError(
                    {'body': 'Group rekey is required before sending after device revoke.'}
                )
            if not body.startswith(GROUP_MESSAGE_PREFIX):
                raise serializers.ValidationError(
                    {'body': 'Group chat messages must use group:v2 payloads.'}
                )
        return attrs


class AttachmentUploadSerializer(serializers.Serializer):
    file = serializers.FileField()


class AttachmentSessionCreateSerializer(serializers.Serializer):
    filename = serializers.CharField()
    mime_type = serializers.CharField()
    cipher_version = serializers.CharField(default='attachment:v1')
    plaintext_size = serializers.IntegerField(min_value=0)
    ciphertext_size = serializers.IntegerField(min_value=0)
    chunk_size = serializers.IntegerField(min_value=1)
    total_chunks = serializers.IntegerField(min_value=1)
    plaintext_sha256 = serializers.CharField()
    manifest_sha256 = serializers.CharField()
    file_key_wrap = serializers.CharField()
    conversation_epoch_id = serializers.CharField(required=False, allow_blank=True, default='')
    recovery_manifest_sequence = serializers.IntegerField(required=False, min_value=0, default=0)

    def validate(self, attrs):
        plaintext_size = attrs.get('plaintext_size', 0)
        ciphertext_size = attrs.get('ciphertext_size', 0)
        chunk_size = attrs.get('chunk_size', 0)
        total_chunks = attrs.get('total_chunks', 0)

        if plaintext_size > settings.ATTACHMENTS_MAX_FILE_BYTES:
            raise serializers.ValidationError(
                {
                    'plaintext_size': (
                        'Attachment exceeds the configured file limit '
                        f'({settings.ATTACHMENTS_MAX_FILE_BYTES} bytes).'
                    )
                }
            )
        if ciphertext_size <= 0 or ciphertext_size < plaintext_size:
            raise serializers.ValidationError(
                {'ciphertext_size': 'Ciphertext size is invalid.'}
            )
        if chunk_size > settings.ATTACHMENTS_MAX_CHUNK_BYTES:
            raise serializers.ValidationError(
                {
                    'chunk_size': (
                        'Chunk size exceeds the configured upload chunk limit '
                        f'({settings.ATTACHMENTS_MAX_CHUNK_BYTES} bytes).'
                    )
                }
            )
        if chunk_size <= 0:
            raise serializers.ValidationError(
                {'chunk_size': 'Chunk size must be greater than zero.'}
            )
        expected_chunks = (plaintext_size + chunk_size - 1) // chunk_size
        if expected_chunks != total_chunks:
            raise serializers.ValidationError(
                {
                    'total_chunks': (
                        'Chunk count does not match the declared plaintext size.'
                    )
                }
            )
        return attrs


class AttachmentSessionCompleteSerializer(serializers.Serializer):
    manifest_sha256 = serializers.CharField(required=False, allow_blank=True, default='')


class AttachmentChunkReceiptSerializer(serializers.ModelSerializer):
    class Meta:
        model = AttachmentChunkReceipt
        fields = [
            'chunk_index',
            'chunk_size',
            'ciphertext_sha256',
            'created_at',
            'updated_at',
        ]


class AttachmentUploadSessionSerializer(serializers.ModelSerializer):
    received_chunks = serializers.SerializerMethodField()
    completed_chunks = serializers.SerializerMethodField()

    class Meta:
        model = AttachmentUploadSession
        fields = [
            'session_id',
            'filename',
            'mime_type',
            'cipher_version',
            'plaintext_size',
            'ciphertext_size',
            'chunk_size',
            'total_chunks',
            'plaintext_sha256',
            'manifest_sha256',
            'file_key_wrap',
            'conversation_epoch_id',
            'recovery_manifest_sequence',
            'blob_storage_key',
            'status',
            'expires_at',
            'created_at',
            'updated_at',
            'received_chunks',
            'completed_chunks',
            'completed_attachment',
        ]

    def get_received_chunks(self, obj):
        return list(obj.chunk_receipts.values_list('chunk_index', flat=True).order_by('chunk_index'))

    def get_completed_chunks(self, obj):
        return obj.chunk_receipts.count()


class MessageAttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = MessageAttachment
        fields = [
            'id',
            'filename',
            'mime_type',
            'size_bytes',
            'storage_key',
            'thumbnail_key',
            'cipher_version',
            'plaintext_size',
            'ciphertext_size',
            'chunk_size',
            'plaintext_sha256',
            'manifest_sha256',
            'file_key_wrap',
            'conversation_epoch_id',
            'recovery_manifest_sequence',
            'created_at',
        ]


class MessageSerializer(serializers.ModelSerializer):
    conversation_id = serializers.IntegerField(source='conversation.id')
    sender_id = serializers.IntegerField(source='sender.id')
    sender_name = serializers.SerializerMethodField()
    client_message_id = serializers.CharField()
    delivery_state = serializers.SerializerMethodField()
    message_type = serializers.CharField()
    attachment_count = serializers.IntegerField()
    attachments = MessageAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = Message
        fields = [
            'id',
            'conversation_id',
            'sender_id',
            'sender_name',
            'client_message_id',
            'delivery_state',
            'message_type',
            'attachment_count',
            'attachments',
            'body',
            'created_at',
        ]

    def get_sender_name(self, obj):
        return obj.sender.first_name or obj.sender.username

    def get_delivery_state(self, _obj):
        return 'sent'


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

    def validate_wrapped_key(self, value):
        if not value.startswith(GROUP_ENVELOPE_PREFIX):
            raise serializers.ValidationError(
                'wrapped_key must use group-wrap:pqc:v2 payloads.'
            )
        return value


class ConversationKeyEnvelopeSyncSerializer(serializers.Serializer):
    key_id = serializers.CharField()
    algorithm = serializers.CharField()
    envelopes = ConversationKeyEnvelopeInputSerializer(many=True)

    def validate_algorithm(self, value):
        if value != GROUP_ENVELOPE_ALGORITHM:
            raise serializers.ValidationError(
                'Only group-ml-kem-768-aesgcm-v2 is accepted.'
            )
        return value


class ConversationSerializer(serializers.ModelSerializer):
    participant_ids = serializers.SerializerMethodField()
    last_message_preview = serializers.SerializerMethodField()
    workspace_id = serializers.IntegerField(source='workspace.id', allow_null=True)

    class Meta:
        model = Conversation
        fields = [
            'id',
            'workspace_id',
            'type',
            'title',
            'participant_ids',
            'last_message_preview',
            'updated_at',
            'created_at',
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


def get_or_create_private_conversation(user, other_user, workspace):
    existing = (
        Conversation.objects.filter(
            type=Conversation.ConversationType.PRIVATE,
            workspace=workspace,
        )
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
        workspace=workspace,
    )
    ConversationParticipant.objects.bulk_create(
        [
            ConversationParticipant(conversation=conversation, user=user),
            ConversationParticipant(conversation=conversation, user=other_user),
        ]
    )
    return conversation, True
