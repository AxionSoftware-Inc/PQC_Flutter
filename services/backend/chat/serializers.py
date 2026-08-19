import re

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
    MessageReaction,
    MessageAttachment,
    ConversationCryptoEpoch,
)
from users.models import Workspace
from chat.protocols import get_protocol_capabilities


User = get_user_model()


class PrivateConversationSerializer(serializers.Serializer):
    other_user_id = serializers.IntegerField()


class MessageCreateSerializer(serializers.Serializer):
    body = serializers.CharField(allow_blank=True, trim_whitespace=True, default='')
    client_message_id = serializers.CharField(
        required=False,
        allow_blank=True,
        max_length=64,
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
        max_length=32,
    )
    reply_to_id = serializers.IntegerField(required=False, allow_null=True)

    def validate(self, attrs):
        body = attrs.get('body', '').strip()
        attachment_ids = attrs.get('attachment_ids') or []
        conversation = self.context.get('conversation')
        if conversation is not None:
            reply_to_id = attrs.get('reply_to_id')
            if reply_to_id is not None and not Message.objects.filter(
                id=reply_to_id,
                conversation=conversation,
            ).exists():
                raise serializers.ValidationError(
                    {'reply_to_id': 'Reply target must belong to this conversation.'}
                )
        if not body and not attachment_ids:
            raise serializers.ValidationError(
                'body or attachment_ids must be provided.'
            )
        if conversation is None or not body:
            return attrs
        if conversation.type == Conversation.ConversationType.PRIVATE:
            allowed = tuple(get_protocol_capabilities()['private_message_prefixes'])
            if not body.startswith(allowed):
                raise serializers.ValidationError(
                    {'body': 'Private chat messages must use a supported encrypted payload.'}
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
            allowed = tuple(get_protocol_capabilities()['group_message_prefixes'])
            if not body.startswith(allowed):
                raise serializers.ValidationError(
                    {'body': 'Group chat messages must use a supported encrypted payload.'}
                )
        return attrs


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
        supported_cipher_versions = set(
            get_protocol_capabilities()['readable_attachment_cipher_versions']
        )
        if attrs.get('cipher_version') not in supported_cipher_versions:
            raise serializers.ValidationError(
                {
                    'cipher_version': (
                        'Attachment cipher version is not enabled on this server.'
                    )
                }
            )
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
        if attrs.get('cipher_version') in {'attachment:v2', 'attachment:v3'}:
            expected_ciphertext_size = plaintext_size + (total_chunks * 16)
            if ciphertext_size != expected_ciphertext_size:
                raise serializers.ValidationError(
                    {
                        'ciphertext_size': (
                            'Authenticated attachment ciphertext must include '
                            'one 16-byte tag per chunk.'
                        )
                    }
                )
            for field_name in ('plaintext_sha256', 'manifest_sha256'):
                value = attrs.get(field_name, '')
                if not re.fullmatch(r'[0-9a-fA-F]{64}', value):
                    raise serializers.ValidationError(
                        {
                            field_name: (
                                'Authenticated attachment manifests require a '
                                '64-character SHA-256 hex digest.'
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
    reactions = serializers.SerializerMethodField()
    reply_to_id = serializers.IntegerField(read_only=True)
    is_read = serializers.SerializerMethodField()

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
            'edited_at',
            'deleted_at',
            'reply_to_id',
            'forwarded_from_id',
            'reactions',
            'is_read',
        ]

    def get_sender_name(self, obj):
        return obj.sender.first_name or obj.sender.username

    def get_delivery_state(self, _obj):
        return 'sent'

    def get_reactions(self, obj):
        reactions = getattr(obj, 'prefetched_reactions', None)
        if reactions is None:
            reactions = obj.reactions.all()
        return [
            {'user_id': reaction.user_id, 'emoji': reaction.emoji}
            for reaction in reactions
        ]

    def get_is_read(self, obj):
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user is None or not user.is_authenticated:
            return False
        receipts = getattr(obj, 'prefetched_receipts', None)
        if obj.sender_id != user.id:
            if receipts is not None:
                return any(
                    receipt.user_id == user.id and receipt.read_at is not None
                    for receipt in receipts
                )
            return obj.receipts.filter(
                user_id=user.id,
                read_at__isnull=False,
            ).exists()
        participants = getattr(
            obj.conversation,
            'prefetched_participants',
            None,
        )
        if participants is None:
            recipient_ids = list(
                obj.conversation.participants.exclude(id=obj.sender_id)
                .values_list('id', flat=True)
            )
        else:
            recipient_ids = [
                participant.id
                for participant in participants
                if participant.id != obj.sender_id
            ]
        if not recipient_ids:
            return False
        if receipts is not None:
            return len({
                receipt.user_id
                for receipt in receipts
                if receipt.user_id in recipient_ids and receipt.read_at is not None
            }) >= len(recipient_ids)
        return obj.receipts.filter(
            user_id__in=recipient_ids,
            read_at__isnull=False,
        ).values('user_id').distinct().count() >= len(recipient_ids)


class MessageReactionSerializer(serializers.ModelSerializer):
    class Meta:
        model = MessageReaction
        fields = ['user_id', 'emoji', 'created_at']
        read_only_fields = ['user_id', 'created_at']


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
        prefixes = tuple(
            get_protocol_capabilities()['readable_group_envelope_prefixes']
        )
        if not value.startswith(prefixes):
            raise serializers.ValidationError(
                'wrapped_key must use an advertised group-key envelope format.'
            )
        return value


class ConversationKeyEnvelopeSyncSerializer(serializers.Serializer):
    key_id = serializers.CharField()
    algorithm = serializers.CharField()
    envelopes = ConversationKeyEnvelopeInputSerializer(many=True)

    def validate_algorithm(self, value):
        allowed = set(get_protocol_capabilities()['group_envelope_algorithms'].values())
        if value not in allowed:
            raise serializers.ValidationError(
                'The group-key envelope algorithm is not enabled on this server. '
                f'Enabled algorithms: {", ".join(sorted(allowed))}.'
            )
        return value

    def validate(self, attrs):
        algorithm_by_prefix = get_protocol_capabilities()['group_envelope_algorithms']
        expected_algorithms = {
            algorithm
            for item in attrs['envelopes']
            for prefix, algorithm in algorithm_by_prefix.items()
            if item['wrapped_key'].startswith(prefix)
        }
        if expected_algorithms and (
            len(expected_algorithms) != 1 or
            attrs['algorithm'] not in expected_algorithms
        ):
            raise serializers.ValidationError(
                {'algorithm': 'Algorithm does not match the envelope prefix.'}
            )
        return attrs


class ConversationSerializer(serializers.ModelSerializer):
    participant_ids = serializers.SerializerMethodField()
    last_message_preview = serializers.SerializerMethodField()
    workspace_id = serializers.IntegerField(source='workspace.id', allow_null=True)
    unread_count = serializers.SerializerMethodField()
    latest_message_id = serializers.SerializerMethodField()
    latest_sender_id = serializers.SerializerMethodField()
    latest_sender_name = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = [
            'id',
            'workspace_id',
            'type',
            'module',
            'module_key',
            'title',
            'participant_ids',
            'last_message_preview',
            'updated_at',
            'created_at',
            'unread_count',
            'latest_message_id',
            'latest_sender_id',
            'latest_sender_name',
        ]

    def get_participant_ids(self, obj):
        participants = getattr(obj, 'ordered_participants', None)
        if participants is not None:
            return [participant.id for participant in participants]
        return list(
            obj.participants.order_by('id').values_list('id', flat=True)
        )

    def get_last_message_preview(self, obj):
        message = self._latest_message(obj)
        if message is None:
            return ''
        return message.body

    def _latest_message(self, obj):
        latest_messages = getattr(obj, 'latest_messages', None)
        if latest_messages is not None:
            return latest_messages[0] if latest_messages else None
        message = getattr(obj, 'latest_message', None)
        if message is None:
            message = obj.messages.select_related('sender').order_by(
                '-created_at', '-id'
            ).first()
        return message

    def get_unread_count(self, obj):
        annotated_count = getattr(obj, 'unread_count_value', None)
        if annotated_count is not None:
            return annotated_count
        request = self.context.get('request')
        user = getattr(request, 'user', None)
        if user is None or not user.is_authenticated:
            return 0
        return obj.messages.exclude(sender_id=user.id).exclude(
            receipts__user_id=user.id,
            receipts__read_at__isnull=False,
        ).distinct().count()

    def get_latest_message_id(self, obj):
        message = self._latest_message(obj)
        return message.id if message is not None else None

    def get_latest_sender_id(self, obj):
        message = self._latest_message(obj)
        return message.sender_id if message is not None else None

    def get_latest_sender_name(self, obj):
        message = self._latest_message(obj)
        if message is None:
            return None
        return message.sender.first_name or message.sender.username


def get_or_create_private_conversation(user, other_user, workspace):
    # A pair has no portable database constraint because the same two users
    # may legitimately have one private conversation per workspace. Lock the
    # workspace row while checking/creating so concurrent workers cannot
    # create duplicate private conversations for the same pair.
    workspace = Workspace.objects.select_for_update().get(pk=workspace.pk)
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
