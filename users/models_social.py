from django.conf import settings
from django.db import models


class UserBlock(models.Model):
    blocker = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='blocked_users')
    blocked = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='blocked_by_users')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['blocker', 'blocked'], name='users_block_unique_pair')]


class UserReport(models.Model):
    reporter = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='submitted_reports')
    target = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='received_reports')
    reason = models.CharField(max_length=64)
    details = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)


class AccountSettings(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='account_settings')
    notifications_enabled = models.BooleanField(default=True)
    notification_previews = models.BooleanField(default=True)
    read_receipts_enabled = models.BooleanField(default=True)
    typing_indicators_enabled = models.BooleanField(default=True)
    last_seen_visibility = models.CharField(max_length=16, default='contacts')
    online_visibility = models.CharField(max_length=16, default='contacts')
    updated_at = models.DateTimeField(auto_now=True)
