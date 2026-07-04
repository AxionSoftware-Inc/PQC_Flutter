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


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        validate_identity_public_key_fields(
            attrs.get('key_algorithm', ''),
            attrs.get('identity_public_key', ''),
        )
        return attrs


class DeviceSerializer(serializers.Serializer):
    device_id = serializers.CharField()
    device_name = serializers.CharField()
    platform = serializers.CharField()
    identity_public_key = serializers.CharField()
    key_algorithm = serializers.CharField()


class DeviceSyncSerializer(serializers.Serializer):
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')

    def validate(self, attrs):
        validate_identity_public_key_fields(
            attrs.get('key_algorithm', ''),
            attrs.get('identity_public_key', ''),
        )
        return attrs


class UserSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    devices = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'display_name', 'devices']

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
                }
                for device in obj.devices.order_by('id')
            ],
            many=True,
        ).data
