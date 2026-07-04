from django.conf import settings
from django.db import models


class UserDevice(models.Model):
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='devices',
    )
    device_id = models.CharField(max_length=255, unique=True)
    device_name = models.CharField(max_length=255, blank=True)
    platform = models.CharField(max_length=64, blank=True)
    identity_public_key = models.TextField(blank=True)
    key_algorithm = models.CharField(max_length=64, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']

    def __str__(self) -> str:
        return f'{self.user.username}:{self.device_id}'
