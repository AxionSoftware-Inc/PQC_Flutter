from django.contrib.auth import get_user_model
from django.db import transaction
from django.utils import timezone
from uuid import uuid4

from rest_framework import permissions, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, ConversationParticipant
from users.models import UserDevice, UserDevicePreKey
from users.serializers import (
    ClaimedDevicePreKeySerializer,
    DeviceSyncSerializer,
    LoginSerializer,
    UserSerializer,
)


User = get_user_model()


def create_account_for_display_name(display_name):
    return User.objects.create(
        username=f'account_{uuid4().hex[:24]}',
        first_name=display_name,
    )


def upsert_user_device(
    *,
    user,
    device_id,
    device_name='',
    platform='',
    identity_public_key='',
    key_algorithm='',
):
    device, device_created = UserDevice.objects.get_or_create(
        device_id=device_id,
        defaults={
            'user': user,
            'device_name': device_name,
            'platform': platform,
            'identity_public_key': identity_public_key,
            'key_algorithm': key_algorithm,
        },
    )
    if not device_created and device.user_id != user.id:
        return None, Response(
            {
                'detail': 'This device is already linked to another username.',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not device_created:
        updated_fields = []
        if device_name and device.device_name != device_name:
            device.device_name = device_name
            updated_fields.append('device_name')
        if platform and device.platform != platform:
            device.platform = platform
            updated_fields.append('platform')
        if identity_public_key and device.identity_public_key != identity_public_key:
            device.identity_public_key = identity_public_key
            updated_fields.append('identity_public_key')
        if key_algorithm and device.key_algorithm != key_algorithm:
            device.key_algorithm = key_algorithm
            updated_fields.append('key_algorithm')
        if updated_fields:
            device.save(update_fields=updated_fields + ['updated_at'])

    return device, None


def sync_device_prekeys(*, device, prekeys):
    if not prekeys:
        return

    incoming_ids = {item['key_id'] for item in prekeys}
    device.prekeys.filter(used_at__isnull=True).exclude(key_id__in=incoming_ids).delete()

    for item in prekeys:
        UserDevicePreKey.objects.update_or_create(
            device=device,
            key_id=item['key_id'],
            defaults={
                'public_key': item['public_key'],
                'used_at': None,
            },
        )


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    @transaction.atomic
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        display_name = ' '.join(
            serializer.validated_data['display_name'].strip().split()
        )
        device_id = serializer.validated_data['device_id'].strip()
        device_name = serializer.validated_data['device_name'].strip()
        platform = serializer.validated_data['platform'].strip()
        identity_public_key = serializer.validated_data['identity_public_key'].strip()
        key_algorithm = serializer.validated_data['key_algorithm'].strip()
        prekeys = serializer.validated_data['prekeys']

        if not display_name or not device_id:
            return Response(
                {'detail': 'display_name and device_id are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing_device = UserDevice.objects.select_related('user').filter(
            device_id=device_id,
        ).first()
        if existing_device is not None:
            user = existing_device.user
        else:
            user = create_account_for_display_name(display_name)

        if display_name and user.first_name != display_name:
            user.first_name = display_name
            user.save(update_fields=['first_name'])

        device, error_response = upsert_user_device(
            user=user,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            identity_public_key=identity_public_key,
            key_algorithm=key_algorithm,
        )
        if error_response is not None:
            return error_response
        sync_device_prekeys(device=device, prekeys=prekeys)

        group, _ = Conversation.objects.get_or_create(
            type=Conversation.ConversationType.GROUP,
            title='General Group',
        )
        ConversationParticipant.objects.get_or_create(
            conversation=group,
            user=user,
        )

        token, _ = Token.objects.get_or_create(user=user)
        return Response(
            {
                'token': token.key,
                'account_id': user.id,
                'device_id': device.device_id,
                'user': UserSerializer(user).data,
            }
        )


class MeView(APIView):
    def get(self, request):
        return Response(UserSerializer(request.user).data)


class UserListView(APIView):
    def get(self, request):
        users = User.objects.order_by('id')
        return Response(UserSerializer(users, many=True).data)


class DeviceSyncView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = DeviceSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        device_id = serializer.validated_data['device_id'].strip()
        if not device_id:
            return Response(
                {'detail': 'device_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        device, error_response = upsert_user_device(
            user=request.user,
            device_id=device_id,
            device_name=serializer.validated_data['device_name'].strip(),
            platform=serializer.validated_data['platform'].strip(),
            identity_public_key=serializer.validated_data['identity_public_key'].strip(),
            key_algorithm=serializer.validated_data['key_algorithm'].strip(),
        )
        if error_response is not None:
            return error_response
        sync_device_prekeys(
            device=device,
            prekeys=serializer.validated_data['prekeys'],
        )

        return Response(
            {
                'device_id': device.device_id,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
            }
        )


class ClaimDevicePreKeyView(APIView):
    @transaction.atomic
    def post(self, request, user_id, device_id):
        if request.user.id == user_id:
            return Response(
                {'detail': 'Cannot claim a prekey from your own device.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        device = UserDevice.objects.select_for_update().filter(
            user_id=user_id,
            device_id=device_id,
        ).first()
        if device is None:
            return Response(
                {'detail': 'Target device was not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        prekey = device.prekeys.filter(used_at__isnull=True).order_by('id').first()
        if prekey is None:
            return Response(
                {'detail': 'No available prekeys for this device.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        prekey.used_at = timezone.now()
        prekey.save(update_fields=['used_at'])

        return Response(
            ClaimedDevicePreKeySerializer(
                {
                    'device_id': device.device_id,
                    'key_id': prekey.key_id,
                    'public_key': prekey.public_key,
                }
            ).data
        )
