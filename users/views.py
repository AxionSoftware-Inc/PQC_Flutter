from django.contrib.auth import get_user_model
from django.db import transaction
from rest_framework import permissions, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, ConversationParticipant
from users.models import UserDevice
from users.serializers import DeviceSyncSerializer, LoginSerializer, UserSerializer


User = get_user_model()


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


class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    @transaction.atomic
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        raw_username = ' '.join(serializer.validated_data['username'].strip().split())
        username = raw_username.lower()
        display_name = raw_username
        device_id = serializer.validated_data['device_id'].strip()
        device_name = serializer.validated_data['device_name'].strip()
        platform = serializer.validated_data['platform'].strip()
        identity_public_key = serializer.validated_data['identity_public_key'].strip()
        key_algorithm = serializer.validated_data['key_algorithm'].strip()

        if not username or not device_id:
            return Response(
                {'detail': 'username and device_id are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user, created = User.objects.get_or_create(
            username=username,
            defaults={'first_name': display_name},
        )
        if not created and display_name and user.first_name != display_name:
            user.first_name = display_name
            user.save(update_fields=['first_name'])

        _, error_response = upsert_user_device(
            user=user,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            identity_public_key=identity_public_key,
            key_algorithm=key_algorithm,
        )
        if error_response is not None:
            return error_response

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

        return Response(
            {
                'device_id': device.device_id,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
            }
        )
