from django.conf import settings
from django.db import models

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
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']

    def __str__(self) -> str:
        return f'{self.conversation_id}:{self.filename}'


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
