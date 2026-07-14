from django.conf import settings
from django.db import models


class Organization(models.Model):
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255, unique=True)
    brand_color = models.CharField(max_length=32, blank=True)
    brand_logo_url = models.URLField(blank=True)
    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='created_organizations',
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']

    def __str__(self) -> str:
        return self.name


class GoogleAccount(models.Model):
    """Stable external identity; device keys remain owned by UserDevice."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='google_account',
    )
    google_subject = models.CharField(max_length=255, unique=True)
    email = models.EmailField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f'{self.user_id}:{self.google_subject}'


class UserCryptoBackup(models.Model):
    """Encrypted client backup; the server must never decrypt this blob."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='crypto_backup',
    )
    version = models.PositiveIntegerField(default=1)
    encrypted_blob = models.TextField()
    blob_sha256 = models.CharField(max_length=64)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f'{self.user_id}:v{self.version}'


class AccountRecoveryManifest(models.Model):
    """Small append-only recovery index; material lives in immutable records."""

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='account_recovery_manifest',
    )
    schema_version = models.PositiveIntegerField(default=2)
    encrypted_payload = models.TextField()
    kms_key_id = models.CharField(max_length=512)
    kms_key_version = models.CharField(max_length=512)
    payload_sha256 = models.CharField(max_length=64)
    sequence = models.PositiveBigIntegerField(default=1)
    vector_clock = models.JSONField(default=dict, blank=True)
    merkle_root = models.CharField(max_length=64, blank=True)
    updated_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self) -> str:
        return f'{self.user_id}:recovery-v{self.schema_version}'


class CryptoRecoveryAuditEvent(models.Model):
    """Append-only audit record for escrow access and recovery lifecycle."""

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    event_type = models.CharField(max_length=64)
    device_id = models.CharField(max_length=255, blank=True)
    metadata = models.JSONField(default=dict, blank=True)
    previous_hash = models.CharField(max_length=64, blank=True)
    event_hash = models.CharField(max_length=64, unique=True, null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['id']


class AccountKeysetEscrowRecord(models.Model):
    """Immutable envelope-encrypted snapshot, never overwritten by another device."""
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    source_device_id = models.CharField(max_length=255)
    keyset_id = models.CharField(max_length=255, blank=True)
    epoch_id = models.CharField(max_length=255, blank=True)
    record_type = models.CharField(max_length=64, default='device_snapshot')
    encrypted_data_key = models.TextField()
    ciphertext = models.TextField()
    nonce = models.CharField(max_length=64)
    kms_key_id = models.CharField(max_length=512)
    encryption_context = models.JSONField(default=dict)
    payload_sha256 = models.CharField(max_length=64)
    state = models.CharField(max_length=32, default='active')
    revoked_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['id']
        constraints = [
            models.UniqueConstraint(
                fields=('user', 'source_device_id', 'payload_sha256'),
                name='users_escrow_record_content_unique',
            ),
        ]


class RecoveryDeviceApproval(models.Model):
    """A recovery read on a new device must be approved by another device."""
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        APPROVED = 'approved', 'Approved'
        DENIED = 'denied', 'Denied'
        EXPIRED = 'expired', 'Expired'

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    requester_device_id = models.CharField(max_length=255)
    approver_device_id = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=16, choices=Status.choices, default=Status.PENDING)
    challenge = models.CharField(max_length=128, unique=True)
    expires_at = models.DateTimeField()
    created_at = models.DateTimeField(auto_now_add=True)
    approved_at = models.DateTimeField(null=True, blank=True)


class Workspace(models.Model):
    organization = models.ForeignKey(
        Organization,
        on_delete=models.CASCADE,
        related_name='workspaces',
    )
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=255)
    policy_flags = models.JSONField(default=dict, blank=True)
    is_default = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']
        unique_together = ('organization', 'slug')

    def __str__(self) -> str:
        return f'{self.organization_id}:{self.name}'


class OrganizationMember(models.Model):
    class Role(models.TextChoices):
        OWNER = 'owner', 'Owner'
        ADMIN = 'admin', 'Admin'
        MEMBER = 'member', 'Member'

    organization = models.ForeignKey(
        Organization,
        on_delete=models.CASCADE,
        related_name='members',
    )
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='organization_memberships',
    )
    role = models.CharField(
        max_length=32,
        choices=Role.choices,
        default=Role.MEMBER,
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']
        unique_together = ('organization', 'user')

    def __str__(self) -> str:
        return f'{self.organization_id}:{self.user_id}:{self.role}'


class WorkspaceMember(models.Model):
    workspace = models.ForeignKey(
        Workspace,
        on_delete=models.CASCADE,
        related_name='members',
    )
    organization_member = models.ForeignKey(
        OrganizationMember,
        on_delete=models.CASCADE,
        related_name='workspace_memberships',
    )
    role = models.CharField(
        max_length=32,
        choices=OrganizationMember.Role.choices,
        default=OrganizationMember.Role.MEMBER,
    )
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']
        unique_together = ('workspace', 'organization_member')

    def __str__(self) -> str:
        return f'{self.workspace_id}:{self.organization_member.user_id}:{self.role}'


class Invitation(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        ACCEPTED = 'accepted', 'Accepted'
        REVOKED = 'revoked', 'Revoked'

    organization = models.ForeignKey(
        Organization,
        on_delete=models.CASCADE,
        related_name='invitations',
    )
    workspace = models.ForeignKey(
        Workspace,
        on_delete=models.CASCADE,
        related_name='invitations',
    )
    invited_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='sent_invitations',
    )
    email = models.EmailField()
    role = models.CharField(
        max_length=32,
        choices=OrganizationMember.Role.choices,
        default=OrganizationMember.Role.MEMBER,
    )
    invite_code = models.CharField(max_length=64, unique=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.PENDING,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-id']

    def __str__(self) -> str:
        return f'{self.email}:{self.workspace_id}:{self.status}'


class UserDevice(models.Model):
    class Status(models.TextChoices):
        ACTIVE = 'active', 'Active'
        INACTIVE = 'inactive', 'Inactive'
        REVOKED = 'revoked', 'Revoked'

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
    pqc_public_key = models.TextField(blank=True)
    pqc_algorithm = models.CharField(max_length=64, blank=True)
    pqc_signing_public_key = models.TextField(blank=True)
    pqc_signing_algorithm = models.CharField(max_length=64, blank=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    replaced_by = models.ForeignKey(
        'self',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='replaced_devices',
    )
    revoked_reason = models.CharField(max_length=255, blank=True)
    profile_fingerprint = models.CharField(max_length=128, blank=True)
    first_seen_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now_add=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['id']

    def __str__(self) -> str:
        return f'{self.user.username}:{self.device_id}'


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


class UserDevicePreKey(models.Model):
    device = models.ForeignKey(
        UserDevice,
        on_delete=models.CASCADE,
        related_name='prekeys',
    )
    key_id = models.CharField(max_length=64)
    public_key = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['id']
        unique_together = ('device', 'key_id')

    def __str__(self) -> str:
        return f'{self.device.device_id}:{self.key_id}'


class HistoricalDeviceKey(models.Model):
    """Immutable public key history retained for old message verification."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='historical_device_keys',
    )
    device_id = models.CharField(max_length=255)
    identity_public_key = models.TextField(blank=True)
    key_algorithm = models.CharField(max_length=64, blank=True)
    pqc_public_key = models.TextField(blank=True)
    pqc_algorithm = models.CharField(max_length=64, blank=True)
    pqc_signing_public_key = models.TextField(blank=True)
    pqc_signing_algorithm = models.CharField(max_length=64, blank=True)
    profile_fingerprint = models.CharField(max_length=128, blank=True)
    captured_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['id']
        constraints = [
            models.UniqueConstraint(
                fields=['user', 'device_id', 'profile_fingerprint'],
                name='users_historical_device_profile_unique',
            ),
        ]
