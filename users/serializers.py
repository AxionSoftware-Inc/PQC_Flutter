from django.contrib.auth import get_user_model
from rest_framework import serializers
import base64


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


class DevicePreKeySerializer(serializers.Serializer):
    key_id = serializers.CharField()
    public_key = serializers.CharField()

    def validate(self, attrs):
        validate_identity_public_key_fields('x25519', attrs.get('public_key', ''))
        return attrs


class ClaimedDevicePreKeySerializer(serializers.Serializer):
    device_id = serializers.CharField()
    key_id = serializers.CharField()
    public_key = serializers.CharField()


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField(required=False, allow_blank=True, default='')
    display_name = serializers.CharField(required=False, allow_blank=True, default='')
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    pqc_signing_algorithm = serializers.CharField(required=False, allow_blank=True, default='')
    prekeys = DevicePreKeySerializer(many=True, required=False, default=list)

    def validate(self, attrs):
        attrs['display_name'] = (
            attrs.get('display_name', '').strip() or attrs.get('username', '').strip()
        )
        if not attrs['display_name']:
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
    prekeys = DevicePreKeySerializer(many=True, required=False)
    created_at = serializers.DateTimeField()
    updated_at = serializers.DateTimeField()


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
    prekeys = DevicePreKeySerializer(many=True, required=False, default=list)

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
    account_id = serializers.IntegerField(source='id')

    class Meta:
        model = User
        fields = ['id', 'account_id', 'username', 'display_name', 'devices']

    def get_username(self, obj):
        return obj.first_name or obj.username

    def get_display_name(self, obj):
        return obj.first_name or obj.username

    def get_devices(self, obj):
        return DeviceSerializer(
            [
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
                    'created_at': device.created_at,
                    'updated_at': device.updated_at,
                    'prekeys': [
                        {
                            'key_id': prekey.key_id,
                            'public_key': prekey.public_key,
                        }
                        for prekey in device.prekeys.filter(used_at__isnull=True).order_by('id')[:10]
                    ],
                }
                for device in obj.devices.order_by('id')
            ],
            many=True,
        ).data
