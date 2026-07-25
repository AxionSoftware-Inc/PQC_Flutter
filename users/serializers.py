import base64
from django.contrib.auth import get_user_model
from rest_framework import serializers

from users.models import Invitation, Organization, OrganizationMember, Workspace, WorkspaceMember
from users.roles import CorporateRole, DEFAULT_CORPORATE_ROLE


User = get_user_model()


def validate_identity_public_key_fields(key_algorithm, identity_public_key):
    if key_algorithm != 'x25519':
        return identity_public_key

    if not identity_public_key:
        raise serializers.ValidationError(
            'identity_public_key is required when key_algorithm is x25519.'
        )

    try:
        decoded = base64.b64decode(identity_public_key, validate=True)
    except Exception as exc:
        raise serializers.ValidationError(
            'identity_public_key must be valid base64 for x25519.'
        ) from exc

    if len(decoded) != 32:
        raise serializers.ValidationError(
            'identity_public_key must decode to 32 bytes for x25519.'
        )

    return identity_public_key


def validate_pqc_public_key_fields(pqc_algorithm, pqc_public_key):
    if not pqc_algorithm:
        return pqc_public_key

    if pqc_algorithm != 'ml-kem-768':
        raise serializers.ValidationError('Unsupported pqc_algorithm.')

    if not pqc_public_key:
        raise serializers.ValidationError(
            'pqc_public_key is required when pqc_algorithm is ml-kem-768.'
        )

    try:
        decoded = base64.b64decode(pqc_public_key, validate=True)
    except Exception as exc:
        raise serializers.ValidationError(
            'pqc_public_key must be valid base64 for ml-kem-768.'
        ) from exc

    if len(decoded) != 1184:
        raise serializers.ValidationError(
            'pqc_public_key must decode to 1184 bytes for ml-kem-768.'
        )

    return pqc_public_key


def validate_pqc_signing_public_key_fields(
    pqc_signing_algorithm,
    pqc_signing_public_key,
):
    if not pqc_signing_algorithm:
        return pqc_signing_public_key

    if pqc_signing_algorithm != 'ml-dsa-65':
        raise serializers.ValidationError('Unsupported pqc_signing_algorithm.')

    if not pqc_signing_public_key:
        raise serializers.ValidationError(
            'pqc_signing_public_key is required when pqc_signing_algorithm is ml-dsa-65.'
        )

    try:
        decoded = base64.b64decode(pqc_signing_public_key, validate=True)
    except Exception as exc:
        raise serializers.ValidationError(
            'pqc_signing_public_key must be valid base64 for ml-dsa-65.'
        ) from exc

    if len(decoded) != 1952:
        raise serializers.ValidationError(
            'pqc_signing_public_key must decode to 1952 bytes for ml-dsa-65.'
        )

    return pqc_signing_public_key


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(required=False, allow_blank=True, default='')
    display_name = serializers.CharField(required=False, allow_blank=True, default='')
    remember_device_only = serializers.BooleanField(required=False, default=False)
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_algorithm = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        attrs['display_name'] = (
            attrs.get('display_name', '').strip() or attrs.get('username', '').strip()
        )
        if not attrs['display_name'] and not attrs.get('remember_device_only', False):
            raise serializers.ValidationError(
                {'display_name': 'display_name is required.'}
            )
        validate_identity_public_key_fields(
            attrs.get('key_algorithm', ''),
            attrs.get('identity_public_key', ''),
        )
        validate_pqc_public_key_fields(
            attrs.get('pqc_algorithm', ''),
            attrs.get('pqc_public_key', ''),
        )
        validate_pqc_signing_public_key_fields(
            attrs.get('pqc_signing_algorithm', ''),
            attrs.get('pqc_signing_public_key', ''),
        )
        return attrs


class DeviceSerializer(serializers.Serializer):
    device_id = serializers.CharField()
    device_name = serializers.CharField()
    platform = serializers.CharField()
    identity_public_key = serializers.CharField()
    key_algorithm = serializers.CharField()
    pqc_public_key = serializers.CharField()
    pqc_algorithm = serializers.CharField()
    pqc_signing_public_key = serializers.CharField()
    pqc_signing_algorithm = serializers.CharField()
    status = serializers.CharField()
    profile_fingerprint = serializers.CharField()
    revoked_reason = serializers.CharField(allow_blank=True, required=False)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()
    first_seen_at = serializers.DateTimeField()
    last_seen_at = serializers.DateTimeField()


class DeviceSyncSerializer(serializers.Serializer):
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_algorithm = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        validate_identity_public_key_fields(
            attrs.get('key_algorithm', ''),
            attrs.get('identity_public_key', ''),
        )
        validate_pqc_public_key_fields(
            attrs.get('pqc_algorithm', ''),
            attrs.get('pqc_public_key', ''),
        )
        validate_pqc_signing_public_key_fields(
            attrs.get('pqc_signing_algorithm', ''),
            attrs.get('pqc_signing_public_key', ''),
        )
        return attrs


class UserSerializer(serializers.ModelSerializer):
    username = serializers.SerializerMethodField()
    display_name = serializers.SerializerMethodField()
    devices = serializers.SerializerMethodField()
    avatar_url = serializers.SerializerMethodField()
    role = serializers.SerializerMethodField()
    role_label = serializers.SerializerMethodField()
    can_manage_role = serializers.SerializerMethodField()
    workspace_member_id = serializers.SerializerMethodField()
    account_id = serializers.IntegerField(source='id')

    class Meta:
        model = User
        fields = [
            'id',
            'account_id',
            'username',
            'display_name',
            'avatar_url',
            'role',
            'role_label',
            'can_manage_role',
            'workspace_member_id',
            'devices',
        ]

    def get_username(self, obj):
        return obj.first_name or obj.username

    def get_display_name(self, obj):
        return obj.first_name or obj.username

    def get_avatar_url(self, obj):
        profile = getattr(obj, 'profile', None)
        if profile is not None and profile.avatar:
            request = self.context.get('request')
            url = profile.avatar.url
            return request.build_absolute_uri(url) if request else url
        account = getattr(obj, 'google_account', None)
        return account.avatar_url if account else ''

    def get_role(self, obj):
        roles = self.context.get('workspace_roles_by_user', {})
        if obj.id in roles:
            return roles[obj.id]
        resolved = getattr(self, '_resolved_roles', {})
        if obj.id in resolved:
            return resolved[obj.id]
        membership = WorkspaceMember.objects.filter(
            organization_member__user=obj,
            organization_member__is_active=True,
            is_active=True,
        ).order_by('-workspace__is_default', 'workspace_id').first()
        role = membership.role if membership else DEFAULT_CORPORATE_ROLE
        resolved[obj.id] = role
        self._resolved_roles = resolved
        return role

    def get_role_label(self, obj):
        value = self.get_role(obj)
        try:
            return CorporateRole(value).label
        except ValueError:
            return CorporateRole.MEMBER.label

    def get_can_manage_role(self, obj):
        return obj.id in self.context.get('manageable_role_user_ids', set())

    def get_workspace_member_id(self, obj):
        return self.context.get('workspace_member_ids_by_user', {}).get(obj.id)

    def get_devices(self, obj):
        device_rows = [
            {
                'device_id': device.device_id,
                'device_name': device.device_name,
                'platform': device.platform,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
                'pqc_public_key': device.pqc_public_key,
                'pqc_algorithm': device.pqc_algorithm,
                'pqc_signing_public_key': device.pqc_signing_public_key,
                'pqc_signing_algorithm': device.pqc_signing_algorithm,
                'status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
                'revoked_reason': device.revoked_reason,
                'created_at': device.created_at,
                'updated_at': device.updated_at,
                'first_seen_at': device.first_seen_at,
                'last_seen_at': device.last_seen_at,
            }
            for device in obj.devices.all().order_by('id')
        ]
        device_rows.extend(
            {
                'device_id': item.device_id,
                'device_name': 'Historical device',
                'platform': 'historical',
                'identity_public_key': item.identity_public_key,
                'key_algorithm': item.key_algorithm,
                'pqc_public_key': item.pqc_public_key,
                'pqc_algorithm': item.pqc_algorithm,
                'pqc_signing_public_key': item.pqc_signing_public_key,
                'pqc_signing_algorithm': item.pqc_signing_algorithm,
                'status': 'historical',
                'profile_fingerprint': item.profile_fingerprint,
                'revoked_reason': '',
                'created_at': item.captured_at,
                'updated_at': item.captured_at,
                'first_seen_at': item.captured_at,
                'last_seen_at': item.captured_at,
            }
            for item in obj.historical_device_keys.all().order_by('id')
        )
        return DeviceSerializer(
            device_rows,
            many=True,
        ).data


class WorkspaceSerializer(serializers.ModelSerializer):
    organization_id = serializers.IntegerField(source='organization.id')

    class Meta:
        model = Workspace
        fields = [
            'id',
            'organization_id',
            'name',
            'slug',
            'policy_flags',
            'is_default',
        ]


class OrganizationSerializer(serializers.ModelSerializer):
    workspaces = serializers.SerializerMethodField()
    current_role = serializers.SerializerMethodField()

    class Meta:
        model = Organization
        fields = [
            'id',
            'name',
            'slug',
            'brand_color',
            'brand_logo_url',
            'current_role',
            'workspaces',
        ]

    def get_workspaces(self, obj):
        memberships = self.context.get('workspace_memberships_by_org', {})
        return WorkspaceSerializer(memberships.get(obj.id, []), many=True).data

    def get_current_role(self, obj):
        roles = self.context.get('roles_by_org', {})
        return roles.get(obj.id, OrganizationMember.Role.MEMBER)


class InvitationSerializer(serializers.ModelSerializer):
    organization_id = serializers.IntegerField(source='organization.id')
    workspace_id = serializers.IntegerField(source='workspace.id')

    class Meta:
        model = Invitation
        fields = [
            'id',
            'organization_id',
            'workspace_id',
            'email',
            'role',
            'invite_code',
            'status',
            'created_at',
            'updated_at',
        ]


class InvitationCreateSerializer(serializers.Serializer):
    workspace_id = serializers.IntegerField()
    email = serializers.EmailField()
    role = serializers.ChoiceField(
        choices=OrganizationMember.Role.choices,
        default=OrganizationMember.Role.MEMBER,
    )


class InvitationAcceptSerializer(serializers.Serializer):
    invite_code = serializers.CharField()


class WorkspaceSwitchSerializer(serializers.Serializer):
    workspace_id = serializers.IntegerField()


class WorkspaceRoleUpdateSerializer(serializers.Serializer):
    role = serializers.ChoiceField(choices=CorporateRole.choices)


class ProfileUpdateSerializer(serializers.Serializer):
    display_name = serializers.CharField(max_length=150)

    def validate_display_name(self, value):
        value = ' '.join(value.split())
        if len(value) < 2:
            raise serializers.ValidationError('Ism kamida 2 ta belgidan iborat bo‘lsin.')
        return value


class WorkspaceMemberSerializer(serializers.ModelSerializer):
    workspace_id = serializers.IntegerField(source='workspace.id')
    user_id = serializers.IntegerField(source='organization_member.user.id')
    display_name = serializers.SerializerMethodField()

    class Meta:
        model = WorkspaceMember
        fields = [
            'id',
            'workspace_id',
            'user_id',
            'display_name',
            'role',
            'is_active',
        ]

    def get_display_name(self, obj):
        return obj.organization_member.user.first_name or obj.organization_member.user.username
