from django.conf import settings
from django.db import models
from django.utils import timezone

from users.models import UserDevice, Workspace


class Conversation(models.Model):
    class ConversationType(models.TextChoices):
        PRIVATE = 'private', 'Private'
        GROUP = 'group', 'Group'

    type = models.CharField(max_length=20, choices=ConversationType.choices)
    title = models.CharField(max_length=255, blank=True)
    workspace = models.ForeignKey(
        Workspace,
        on_delete=models.CASCADE,
        related_name='conversations',
        null=True,
        blank=True,
    )
    participants = models.ManyToManyField(
        settings.AUTH_USER_MODEL,
        through='ConversationParticipant',
        related_name='conversations',
    )
    updated_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-updated_at', '-id']

    def __str__(self) -> str:
        return self.title or f'{self.type}:{self.pk}'


class ConversationParticipant(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('conversation', 'user')


class Message(models.Model):
    class MessageType(models.TextChoices):
        TEXT = 'text', 'Text'
        FILE = 'file', 'File'
        IMAGE = 'image', 'Image'

    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    body = models.TextField()
    client_message_id = models.CharField(max_length=64, blank=True)
    message_type = models.CharField(
        max_length=16,
        choices=MessageType.choices,
        default=MessageType.TEXT,
    )
    attachment_count = models.PositiveIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at', 'id']
        constraints = [
            models.UniqueConstraint(
                fields=['conversation', 'sender', 'client_message_id'],
                condition=~models.Q(client_message_id=''),
                name='chat_unique_client_message_per_sender',
            ),
        ]

    def __str__(self) -> str:
        return f'{self.sender_id}:{self.body[:30]}'


class MessageReceipt(models.Model):
    """Per-recipient delivery/read watermark for realtime and offline clients."""

    message = models.ForeignKey(
        Message,
        on_delete=models.CASCADE,
        related_name='receipts',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='message_receipts',
    )
    delivered_at = models.DateTimeField(null=True, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=['message', 'user'],
                name='chat_message_receipt_unique_recipient',
            ),
        ]


class MessageAttachment(models.Model):
    message = models.ForeignKey(
        Message,
        on_delete=models.CASCADE,
        related_name='attachments',
        null=True,
        blank=True,
    )
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='attachments',
    )
    workspace = models.ForeignKey(
        Workspace,
        on_delete=models.CASCADE,
        related_name='attachments',
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='uploaded_attachments',
    )
    filename = models.CharField(max_length=255)
    mime_type = models.CharField(max_length=255)
    size_bytes = models.BigIntegerField(default=0)
    storage_key = models.CharField(max_length=512)
    thumbnail_key = models.CharField(max_length=512, blank=True)
    cipher_version = models.CharField(max_length=64, default='attachment:v1')
    plaintext_size = models.BigIntegerField(default=0)
    ciphertext_size = models.BigIntegerField(default=0)
    chunk_size = models.PositiveIntegerField(default=0)
    plaintext_sha256 = models.CharField(max_length=128, blank=True)
    manifest_sha256 = models.CharField(max_length=128, blank=True)
    file_key_wrap = models.TextField(blank=True)
    conversation_epoch_id = models.CharField(max_length=128, blank=True)
    recovery_manifest_sequence = models.PositiveBigIntegerField(default=0)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']

    def __str__(self) -> str:
        return f'{self.conversation_id}:{self.filename}'


class AttachmentUploadSession(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        UPLOADING = 'uploading', 'Uploading'
        COMPLETED = 'completed', 'Completed'
        ABORTED = 'aborted', 'Aborted'
        EXPIRED = 'expired', 'Expired'

    session_id = models.CharField(max_length=64, unique=True)
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='attachment_upload_sessions',
    )
    workspace = models.ForeignKey(
        Workspace,
        on_delete=models.CASCADE,
        related_name='attachment_upload_sessions',
    )
    uploaded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='attachment_upload_sessions',
    )
    completed_attachment = models.OneToOneField(
        MessageAttachment,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name='upload_session',
    )
    filename = models.CharField(max_length=255)
    mime_type = models.CharField(max_length=255)
    cipher_version = models.CharField(max_length=64, default='attachment:v1')
    plaintext_size = models.BigIntegerField(default=0)
    ciphertext_size = models.BigIntegerField(default=0)
    chunk_size = models.PositiveIntegerField(default=0)
    total_chunks = models.PositiveIntegerField(default=0)
    plaintext_sha256 = models.CharField(max_length=128)
    manifest_sha256 = models.CharField(max_length=128)
    file_key_wrap = models.TextField()
    conversation_epoch_id = models.CharField(max_length=128, blank=True)
    recovery_manifest_sequence = models.PositiveBigIntegerField(default=0)
    blob_storage_key = models.CharField(max_length=512, blank=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.PENDING,
    )
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at', '-id']

    def __str__(self) -> str:
        return f'{self.session_id}:{self.filename}'

    @property
    def is_expired(self) -> bool:
        return self.expires_at <= timezone.now()


class AttachmentChunkReceipt(models.Model):
    session = models.ForeignKey(
        AttachmentUploadSession,
        on_delete=models.CASCADE,
        related_name='chunk_receipts',
    )
    chunk_index = models.PositiveIntegerField()
    chunk_size = models.PositiveIntegerField(default=0)
    ciphertext_sha256 = models.CharField(max_length=128)
    storage_key = models.CharField(max_length=512)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['chunk_index']
        unique_together = ('session', 'chunk_index')

    def __str__(self) -> str:
        return f'{self.session.session_id}:{self.chunk_index}'


class ConversationCryptoEpoch(models.Model):
    class State(models.TextChoices):
        PENDING = 'pending', 'Pending'
        ACTIVE = 'active', 'Active'
        CLOSED = 'closed', 'Closed'

    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name='crypto_epochs',
    )
    epoch_id = models.CharField(max_length=64, unique=True)
    state = models.CharField(max_length=16, choices=State.choices, default=State.PENDING)
    reason = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    activated_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-id']


class ConversationKeyEnvelope(models.Model):
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='key_envelopes',
    )
    target_device = models.ForeignKey(
        UserDevice,
        on_delete=models.CASCADE,
        related_name='conversation_key_envelopes',
    )
    sender_device = models.ForeignKey(
        UserDevice,
        on_delete=models.CASCADE,
        related_name='sent_conversation_key_envelopes',
    )
    key_id = models.CharField(max_length=64)
    algorithm = models.CharField(max_length=64)
    wrapped_key = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-updated_at', '-id']
        unique_together = ('conversation', 'target_device', 'key_id')

    def __str__(self) -> str:
        return f'{self.conversation_id}:{self.target_device.device_id}:{self.key_id}'
