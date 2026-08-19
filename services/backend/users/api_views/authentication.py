import hashlib
import json
import base64
import logging
import secrets
from datetime import timedelta
from urllib.parse import urlencode
from urllib.request import urlopen

from django.conf import settings
from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone
from django.utils.text import slugify
from uuid import uuid4

from rest_framework import permissions, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, ConversationCryptoEpoch, ConversationParticipant
from users.models import (
    Invitation,
    GoogleAccount,
    Organization,
    OrganizationMember,
    UserDevice,
    Workspace,
    WorkspaceMember,
    UserCryptoBackup,
    AccountRecoveryManifest,
    AccountKeysetEscrowRecord,
    RecoveryDeviceApproval,
    RecoveryAccessGrant,
    CryptoRecoveryAuditEvent,
    HistoricalDeviceKey,
    UserBlock, UserReport, AccountSettings,
)
from users.escrow import EscrowEnvelope, get_key_escrow_provider
from users.audit import append_recovery_audit_event
from users.serializers import (
    DeviceSerializer,
    DeviceSyncSerializer,
    InvitationAcceptSerializer,
    InvitationCreateSerializer,
    InvitationSerializer,
    LoginSerializer,
    normalize_supported_protocols,
    OrganizationSerializer,
    UserSerializer,
    WorkspaceMemberSerializer,
    WorkspaceSerializer,
    WorkspaceSwitchSerializer,
)


User = get_user_model()
logger = logging.getLogger(__name__)



from .common import (
    _ensure_default_workspace_membership,
    _find_user_by_device_signature,
    _issue_recovery_access_grant,
    _rotate_recovery_device_credential,
    _serialize_org_context,
    create_account_for_display_name,
    upsert_user_device,
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
        pqc_public_key = serializer.validated_data['pqc_public_key'].strip()
        pqc_algorithm = serializer.validated_data['pqc_algorithm'].strip()
        pqc_signing_public_key = serializer.validated_data['pqc_signing_public_key'].strip()
        pqc_signing_algorithm = serializer.validated_data['pqc_signing_algorithm'].strip()
        supported_protocols = serializer.validated_data['supported_protocols']
        remember_device_only = serializer.validated_data.get('remember_device_only', False)

        if not display_name or not device_id:
            if not remember_device_only:
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
            user = _find_user_by_device_signature(
                device_name=device_name,
                platform=platform,
            )
            if user is None and remember_device_only:
                return Response(
                    {
                        'detail': 'No remembered device account was found.',
                        'code': 'remembered_device_not_found',
                    },
                    status=status.HTTP_404_NOT_FOUND,
                )
            if user is None:
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
            pqc_public_key=pqc_public_key,
            pqc_algorithm=pqc_algorithm,
            pqc_signing_public_key=pqc_signing_public_key,
            pqc_signing_algorithm=pqc_signing_algorithm,
            supported_protocols=supported_protocols,
        )
        if error_response is not None:
            return error_response

        organization, workspace = _ensure_default_workspace_membership(user)

        group, _ = Conversation.objects.get_or_create(
            type=Conversation.ConversationType.GROUP,
            title='General Group',
            workspace=workspace,
        )
        ConversationParticipant.objects.get_or_create(
            conversation=group,
            user=user,
        )

        token, _ = Token.objects.get_or_create(user=user)
        recovery_device_credential = _rotate_recovery_device_credential(device)
        return Response(
            {
                'token': token.key,
                'recovery_device_credential': recovery_device_credential,
                'account_id': user.id,
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
                'active_workspace_id': workspace.id,
                'organizations': _serialize_org_context(user),
                'active_devices': DeviceSerializer(
                    [
                        {
                            'device_id': item.device_id,
                            'device_name': item.device_name,
                            'platform': item.platform,
                            'identity_public_key': item.identity_public_key,
                            'key_algorithm': item.key_algorithm,
                            'pqc_public_key': item.pqc_public_key,
                            'pqc_algorithm': item.pqc_algorithm,
                            'pqc_signing_public_key': item.pqc_signing_public_key,
                            'pqc_signing_algorithm': item.pqc_signing_algorithm,
                            'supported_protocols': item.supported_protocols,
                            'status': item.status,
                            'profile_fingerprint': item.profile_fingerprint,
                            'revoked_reason': item.revoked_reason,
                            'created_at': item.created_at,
                            'updated_at': item.updated_at,
                            'first_seen_at': item.first_seen_at,
                            'last_seen_at': item.last_seen_at,
                        }
                        for item in user.devices.filter(status=UserDevice.Status.ACTIVE).order_by('id')
                    ],
                    many=True,
                ).data,
                'user': UserSerializer(
                    user,
                    context={'request': request},
                ).data,
            }
        )


class GoogleLoginView(APIView):
    permission_classes = [permissions.AllowAny]

    @transaction.atomic
    def post(self, request):
        id_token = str(request.data.get('id_token', '')).strip()
        if not id_token:
            return Response({'detail': 'Google id_token is required.'}, status=400)
        try:
            query = urlencode({'id_token': id_token})
            with urlopen(
                f'https://oauth2.googleapis.com/tokeninfo?{query}', timeout=5
            ) as response:
                claims = json.loads(response.read().decode('utf-8'))
        except Exception:
            return Response({'detail': 'Google token is invalid.'}, status=401)
        if claims.get('aud') != settings.GOOGLE_ANDROID_CLIENT_ID:
            return Response({'detail': 'Google token audience is invalid.'}, status=401)
        if claims.get('email_verified') not in {'true', True} or not claims.get('sub'):
            return Response({'detail': 'Verified Google account is required.'}, status=401)

        subject = str(claims['sub'])
        email = str(claims.get('email', '')).strip().lower()
        identity = GoogleAccount.objects.select_related('user').filter(
            google_subject=subject,
        ).first()
        user = identity.user if identity else User.objects.filter(email__iexact=email).first()
        if user is None:
            user = create_account_for_display_name(
                str(claims.get('name') or email.split('@')[0] or 'Google user')
            )
        if user.email != email:
            user.email = email
            user.save(update_fields=['email'])
        GoogleAccount.objects.update_or_create(
            user=user,
            defaults={'google_subject': subject, 'email': email},
        )
        device, error_response = upsert_user_device(
            user=user,
            device_id=str(request.data.get('device_id', '')).strip(),
            device_name=str(request.data.get('device_name', '')).strip(),
            platform=str(request.data.get('platform', '')).strip(),
            identity_public_key=str(request.data.get('identity_public_key', '')).strip(),
            key_algorithm=str(request.data.get('key_algorithm', '')).strip(),
            pqc_public_key=str(request.data.get('pqc_public_key', '')).strip(),
            pqc_algorithm=str(request.data.get('pqc_algorithm', '')).strip(),
            pqc_signing_public_key=str(request.data.get('pqc_signing_public_key', '')).strip(),
            pqc_signing_algorithm=str(request.data.get('pqc_signing_algorithm', '')).strip(),
            supported_protocols=normalize_supported_protocols(
                request.data.get('supported_protocols')
            ),
        )
        if error_response is not None:
            return error_response
        _, workspace = _ensure_default_workspace_membership(user)
        group, _ = Conversation.objects.get_or_create(
            type=Conversation.ConversationType.GROUP,
            title='General Group',
            workspace=workspace,
        )
        ConversationParticipant.objects.get_or_create(conversation=group, user=user)
        token, _ = Token.objects.get_or_create(user=user)
        recovery_device_credential = _rotate_recovery_device_credential(device)
        recovery_grant = _issue_recovery_access_grant(
            user=user,
            device_id=device.device_id,
        )
        return Response({
            'token': token.key,
            'recovery_device_credential': recovery_device_credential,
            'recovery_grant': recovery_grant,
            'account_id': user.id,
            'device_id': device.device_id,
            'device_status': device.status,
            'profile_fingerprint': device.profile_fingerprint,
            'active_workspace_id': workspace.id,
            'organizations': _serialize_org_context(user),
            'user': UserSerializer(
                user,
                context={'request': request},
            ).data,
        })

