from django.conf import settings
from django.db import models

from users.models import UserDevice


class Conversation(models.Model):
    class ConversationType(models.TextChoices):
        PRIVATE = 'private', 'Private'
        GROUP = 'group', 'Group'

    type = models.CharField(max_length=20, choices=ConversationType.choices)
    title = models.CharField(max_length=255, blank=True)
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
    conversation = models.ForeignKey(
        Conversation,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    body = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at', 'id']

    def __str__(self) -> str:
        return f'{self.sender_id}:{self.body[:30]}'


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
