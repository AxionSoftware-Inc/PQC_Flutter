from django.contrib.auth import get_user_model
from rest_framework import serializers


User = get_user_model()


class LoginSerializer(serializers.Serializer):
    username = serializers.CharField()
    device_id = serializers.CharField()
    device_name = serializers.CharField(required=False, allow_blank=True, default='')
    platform = serializers.CharField(required=False, allow_blank=True, default='')
    identity_public_key = serializers.CharField(required=False, allow_blank=True, default='')
    key_algorithm = serializers.CharField(required=False, allow_blank=True, default='')


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
