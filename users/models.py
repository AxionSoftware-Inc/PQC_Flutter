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
