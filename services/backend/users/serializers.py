import base64
import hashlib
import json
from django.contrib.auth import get_user_model
from django.core.exceptions import ObjectDoesNotExist
from rest_framework import serializers

from users.models import (
    Invitation,
    Organization,
    OrganizationMember,
    Workspace,
    WorkspaceMember,
)


User = get_user_model()
ML_KEM_768_PUBLIC_KEY_BYTES = 1184
ML_KEM_POLYVEC_BYTES = 1152
ML_KEM_Q = 3329
SUPPORTED_PROTOCOL_IDS = ('v2', 'v2.5', 'v3')


def avatar_url_for_user(user, request=None):
    try:
        settings_obj = user.account_settings
    except (AttributeError, ObjectDoesNotExist):
        return ''
    if not settings_obj.avatar_storage_key:
        return ''
    path = f'/api/users/{user.id}/avatar'
    return request.build_absolute_uri(path) if request is not None else path


def normalize_supported_protocols(value):
    """Return a canonical, monotonic protocol capability list.

    V2.5 and V3 clients can read the earlier formats, so a higher capability
    must include the lower protocol ids. Missing legacy data is deliberately
    treated as V2 instead of assuming that a device has been upgraded.
    """
    if value is None or value == '' or value == []:
        return ['v2']
    if isinstance(value, str):
        value = [value]
    if not isinstance(value, (list, tuple, set)):
        raise serializers.ValidationError('supported_protocols must be a list.')

    aliases = {'v25': 'v2.5', 'v2_5': 'v2.5'}
    normalized = set()
    for item in value:
        protocol_id = str(item).strip().lower()
        protocol_id = aliases.get(protocol_id, protocol_id)
        if protocol_id not in SUPPORTED_PROTOCOL_IDS:
            raise serializers.ValidationError(
                f'Unsupported protocol capability: {protocol_id}.'
            )
        normalized.add(protocol_id)
    if not normalized:
        return ['v2']
    if 'v3' in normalized:
        normalized.update(('v2', 'v2.5'))
    elif 'v2.5' in normalized:
        normalized.add('v2')
    return [item for item in SUPPORTED_PROTOCOL_IDS if item in normalized]


def device_keyset_id(device_id, pqc_public_key):
    digest = hashlib.sha256(f'{device_id}|{pqc_public_key}'.encode()).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip('=')


def device_keyset_binding_id(device_id, pqc_public_key, pqc_signing_public_key):
    """Bind the KEM and signing keys for post-V2 protocol releases.

    V2's ``device_keyset_id`` is frozen and must remain KEM-only.  New wire
    formats use this second identifier so replacing a signing key cannot
    leave the old KEM-based identity apparently unchanged.
    """
    canonical = (
        '{"device_id":'
        + json.dumps(device_id, ensure_ascii=False, separators=(',', ':'))
        + ',"kem_public_key":'
        + json.dumps(pqc_public_key, ensure_ascii=False, separators=(',', ':'))
        + ',"signing_public_key":'
        + json.dumps(
            pqc_signing_public_key,
            ensure_ascii=False,
            separators=(',', ':'),
        )
        + '}'
    ).encode('utf-8')
    digest = hashlib.sha256(canonical).digest()
    return base64.urlsafe_b64encode(digest).decode().rstrip('=')


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


def decode_valid_ml_kem_768_public_key(pqc_public_key):
    """Decode and structurally validate an ML-KEM-768 public key.

    Length-only checks accept random 1184-byte blobs.  ML-KEM's encoded
    polynomial coefficients must each be below q; rejecting non-canonical
    encodings here prevents a single corrupt device record from breaking
    private or group encryption on every client.
    """
    try:
        decoded = base64.b64decode(pqc_public_key, validate=True)
    except Exception as exc:
        raise serializers.ValidationError(
            'pqc_public_key must be valid base64 for ml-kem-768.'
        ) from exc

    if len(decoded) != ML_KEM_768_PUBLIC_KEY_BYTES:
        raise serializers.ValidationError(
            'pqc_public_key must decode to 1184 bytes for ml-kem-768.'
        )

    encoded_polyvec = decoded[:ML_KEM_POLYVEC_BYTES]
    for offset in range(0, len(encoded_polyvec), 3):
        first = encoded_polyvec[offset] | ((encoded_polyvec[offset + 1] & 0x0F) << 8)
        second = (encoded_polyvec[offset + 1] >> 4) | (encoded_polyvec[offset + 2] << 4)
        if first >= ML_KEM_Q or second >= ML_KEM_Q:
            raise serializers.ValidationError(
                'pqc_public_key has a non-canonical ml-kem-768 polynomial encoding.'
            )
    return decoded


def is_valid_ml_kem_768_public_key(pqc_public_key):
    try:
        decode_valid_ml_kem_768_public_key(pqc_public_key)
        return True
    except serializers.ValidationError:
        return False


def validate_pqc_public_key_fields(pqc_algorithm, pqc_public_key):
    if not pqc_algorithm:
        return pqc_public_key

    if pqc_algorithm != 'ml-kem-768':
        raise serializers.ValidationError('Unsupported pqc_algorithm.')

    if not pqc_public_key:
        raise serializers.ValidationError(
            'pqc_public_key is required when pqc_algorithm is ml-kem-768.'
        )

    decode_valid_ml_kem_768_public_key(pqc_public_key)

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
    supported_protocols = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list,
    )

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
        attrs['supported_protocols'] = normalize_supported_protocols(
            attrs.get('supported_protocols')
        )
        return attrs


class DeviceSerializer(serializers.Serializer):
    keyset_id = serializers.SerializerMethodField()
    keyset_binding_id = serializers.SerializerMethodField()
    device_id = serializers.CharField()
    device_name = serializers.CharField()
    platform = serializers.CharField()
    identity_public_key = serializers.CharField()
    key_algorithm = serializers.CharField()
    pqc_public_key = serializers.CharField()
    pqc_algorithm = serializers.CharField()
    pqc_signing_public_key = serializers.CharField()
    pqc_signing_algorithm = serializers.CharField()
    supported_protocols = serializers.SerializerMethodField()
    status = serializers.CharField()
    profile_fingerprint = serializers.CharField()
    revoked_reason = serializers.CharField(allow_blank=True, required=False)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()
    first_seen_at = serializers.DateTimeField()
    last_seen_at = serializers.DateTimeField()

    @staticmethod
    def _value(device, field):
        if isinstance(device, dict):
            return device.get(field, '')
        return getattr(device, field, '')

    def get_keyset_id(self, device):
        return device_keyset_id(
            self._value(device, 'device_id'),
            self._value(device, 'pqc_public_key'),
        )

    def get_keyset_binding_id(self, device):
        return device_keyset_binding_id(
            self._value(device, 'device_id'),
            self._value(device, 'pqc_public_key'),
            self._value(device, 'pqc_signing_public_key'),
        )

    def get_supported_protocols(self, device):
        return normalize_supported_protocols(
            self._value(device, 'supported_protocols')
        )


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
    supported_protocols = serializers.ListField(
        child=serializers.CharField(),
        required=False,
        default=list,
    )

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
        attrs['supported_protocols'] = normalize_supported_protocols(
            attrs.get('supported_protocols')
        )
        return attrs


class UserSerializer(serializers.ModelSerializer):
    username = serializers.SerializerMethodField()
    display_name = serializers.SerializerMethodField()
    devices = serializers.SerializerMethodField()
    avatar_url = serializers.SerializerMethodField()
    account_id = serializers.IntegerField(source='id')

    class Meta:
        model = User
        fields = [
            'id',
            'account_id',
            'username',
            'display_name',
            'avatar_url',
            'devices',
        ]

    def get_username(self, obj):
        return obj.first_name or obj.username

    def get_display_name(self, obj):
        return obj.first_name or obj.username

    def get_avatar_url(self, obj):
        return avatar_url_for_user(obj, self.context.get('request'))

    def get_devices(self, obj):
        device_rows = [
            {
                'device_id': device.device_id,
                'keyset_id': device_keyset_id(device.device_id, device.pqc_public_key),
                'device_name': device.device_name,
                'platform': device.platform,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
                'pqc_public_key': device.pqc_public_key,
                'pqc_algorithm': device.pqc_algorithm,
                'pqc_signing_public_key': device.pqc_signing_public_key,
                'pqc_signing_algorithm': device.pqc_signing_algorithm,
                'supported_protocols': normalize_supported_protocols(
                    device.supported_protocols
                ),
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
                'keyset_id': device_keyset_id(item.device_id, item.pqc_public_key),
                'device_name': 'Historical device',
                'platform': 'historical',
                'identity_public_key': item.identity_public_key,
                'key_algorithm': item.key_algorithm,
                'pqc_public_key': item.pqc_public_key,
                'pqc_algorithm': item.pqc_algorithm,
                'pqc_signing_public_key': item.pqc_signing_public_key,
                'pqc_signing_algorithm': item.pqc_signing_algorithm,
                'supported_protocols': ['v2'],
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
