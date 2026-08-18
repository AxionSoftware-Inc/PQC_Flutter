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



from .common import _get_request_active_workspace, _serialize_org_context

class MeView(APIView):
    def get(self, request):
        workspace, error_response = _get_request_active_workspace(request)
        if error_response is not None:
            return error_response
        user_data = UserSerializer(request.user).data
        return Response(
            {
                **user_data,
                'active_workspace_id': workspace.id,
                'organizations': _serialize_org_context(request.user),
                'user': user_data,
            }
        )

    def patch(self, request):
        display_name = str(request.data.get('display_name', '')).strip()
        email = str(request.data.get('email', '')).strip()
        if not display_name and not email:
            return Response({'detail': 'display_name or email is required.'}, status=400)
        updates = []
        if display_name:
            request.user.first_name = display_name
            updates.append('first_name')
        if email:
            request.user.email = email
            updates.append('email')
        if updates:
            request.user.save(update_fields=updates)
        return Response(UserSerializer(request.user).data)


class AccountSettingsView(APIView):
    def get(self, request):
        settings_obj, _ = AccountSettings.objects.get_or_create(user=request.user)
        return Response({field: getattr(settings_obj, field) for field in (
            'notifications_enabled', 'notification_previews', 'read_receipts_enabled',
            'typing_indicators_enabled', 'last_seen_visibility', 'online_visibility')})

    def patch(self, request):
        settings_obj, _ = AccountSettings.objects.get_or_create(user=request.user)
        allowed = {'notifications_enabled', 'notification_previews', 'read_receipts_enabled', 'typing_indicators_enabled', 'last_seen_visibility', 'online_visibility'}
        for key, value in request.data.items():
            if key in allowed:
                setattr(settings_obj, key, value)
        settings_obj.save()
        return Response({field: getattr(settings_obj, field) for field in allowed})


class UserBlockView(APIView):
    def post(self, request, user_id):
        if request.user.id == user_id:
            return Response({'detail': 'Cannot block yourself.'}, status=400)
        target = User.objects.filter(id=user_id).first()
        if target is None:
            return Response({'detail': 'User not found.'}, status=404)
        UserBlock.objects.get_or_create(blocker=request.user, blocked=target)
        return Response({'blocked': True, 'user_id': user_id})

    def delete(self, request, user_id):
        UserBlock.objects.filter(blocker=request.user, blocked_id=user_id).delete()
        return Response(status=204)


class UserReportView(APIView):
    def post(self, request, user_id):
        if request.user.id == user_id:
            return Response({'detail': 'Cannot report yourself.'}, status=400)
        target = User.objects.filter(id=user_id).first()
        if target is None:
            return Response({'detail': 'User not found.'}, status=404)
        reason = str(request.data.get('reason', '')).strip()[:64]
        if not reason:
            return Response({'detail': 'reason is required.'}, status=400)
        report = UserReport.objects.create(reporter=request.user, target=target, reason=reason, details=str(request.data.get('details', '')).strip())
        return Response({'id': report.id, 'created': True}, status=201)


