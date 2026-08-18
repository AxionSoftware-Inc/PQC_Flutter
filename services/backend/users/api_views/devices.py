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
    _get_request_active_workspace,
    _resolve_active_workspace_for_user,
    _serialize_org_context,
    upsert_user_device,
)

class UserListView(APIView):
    def get(self, request):
        workspace, error_response = _get_request_active_workspace(request)
        if error_response is not None:
            return error_response
        users = User.objects.filter(
            organization_memberships__workspace_memberships__workspace=workspace,
            organization_memberships__workspace_memberships__is_active=True,
        ).distinct().order_by('id')
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
            pqc_public_key=serializer.validated_data['pqc_public_key'].strip(),
            pqc_algorithm=serializer.validated_data['pqc_algorithm'].strip(),
            pqc_signing_public_key=serializer.validated_data['pqc_signing_public_key'].strip(),
            pqc_signing_algorithm=serializer.validated_data['pqc_signing_algorithm'].strip(),
            supported_protocols=serializer.validated_data['supported_protocols'],
        )
        if error_response is not None:
            return error_response

        return Response(
            {
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
                'pqc_public_key': device.pqc_public_key,
                'pqc_algorithm': device.pqc_algorithm,
                'pqc_signing_public_key': device.pqc_signing_public_key,
                'pqc_signing_algorithm': device.pqc_signing_algorithm,
                'supported_protocols': normalize_supported_protocols(
                    device.supported_protocols
                ),
                'organizations': _serialize_org_context(request.user),
            }
        )


class DeviceListView(APIView):
    def get(self, request):
        devices = request.user.devices.filter(status=UserDevice.Status.ACTIVE).order_by('id')
        return Response(
            DeviceSerializer(
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
                        'status': device.status,
                        'profile_fingerprint': device.profile_fingerprint,
                        'revoked_reason': device.revoked_reason,
                        'created_at': device.created_at,
                        'updated_at': device.updated_at,
                        'first_seen_at': device.first_seen_at,
                        'last_seen_at': device.last_seen_at,
                    }
                    for device in devices
                ],
                many=True,
            ).data
        )


class DeviceRevokeView(APIView):
    @transaction.atomic
    def post(self, request, device_id):
        device = UserDevice.objects.filter(
            user=request.user,
            device_id=device_id,
        ).first()
        if device is None:
            return Response(
                {'detail': 'Device not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        if device.status == UserDevice.Status.REVOKED:
            return Response(
                {
                    'device_id': device.device_id,
                    'device_status': device.status,
                    'profile_fingerprint': device.profile_fingerprint,
                }
            )
        device.status = UserDevice.Status.REVOKED
        device.revoked_reason = 'revoked_by_user'
        device.last_seen_at = timezone.now()
        device.save(update_fields=['status', 'revoked_reason', 'last_seen_at', 'updated_at'])
        AccountKeysetEscrowRecord.objects.filter(
            user=request.user, source_device_id=device.device_id, state='active',
        ).update(state='revoked', revoked_at=timezone.now())
        group_conversation_ids = ConversationParticipant.objects.filter(
            user=request.user,
            conversation__type=Conversation.ConversationType.GROUP,
        ).values_list('conversation_id', flat=True)
        for conversation_id in group_conversation_ids:
            ConversationCryptoEpoch.objects.get_or_create(
                conversation_id=conversation_id,
                epoch_id=f'rekey-required-{uuid4().hex[:32]}',
                defaults={'state': ConversationCryptoEpoch.State.PENDING, 'reason': 'device_revoked'},
            )
        append_recovery_audit_event(
            user=request.user, event_type='device_revoked', device_id=device.device_id,
            metadata={'rekey_required_conversation_ids': list(group_conversation_ids)},
        )
        return Response(
            {
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
            }
        )


class OrganizationListView(APIView):
    def get(self, request):
        return Response(_serialize_org_context(request.user))


class WorkspaceSwitchView(APIView):
    def post(self, request):
        serializer = WorkspaceSwitchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        workspace = _resolve_active_workspace_for_user(
            request.user,
            str(serializer.validated_data['workspace_id']),
        )
        if workspace is None:
            return Response(
                {'detail': 'Workspace not found for this user.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(
            {
                'active_workspace_id': workspace.id,
                'workspace': WorkspaceSerializer(workspace).data,
            }
        )


class InvitationListCreateView(APIView):
    @transaction.atomic
    def get(self, request):
        invitations = Invitation.objects.filter(
            workspace__members__organization_member__user=request.user,
        ).distinct().order_by('-id')
        return Response(InvitationSerializer(invitations, many=True).data)

    @transaction.atomic
    def post(self, request):
        serializer = InvitationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        workspace = Workspace.objects.filter(
            id=serializer.validated_data['workspace_id'],
            members__organization_member__user=request.user,
            members__role__in=[
                OrganizationMember.Role.OWNER,
                OrganizationMember.Role.ADMIN,
            ],
            members__is_active=True,
        ).select_related('organization').first()
        if workspace is None:
            return Response(
                {'detail': 'Workspace not found or admin rights missing.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        invitation = Invitation.objects.create(
            organization=workspace.organization,
            workspace=workspace,
            invited_by=request.user,
            email=serializer.validated_data['email'],
            role=serializer.validated_data['role'],
            invite_code=uuid4().hex,
        )
        return Response(
            InvitationSerializer(invitation).data,
            status=status.HTTP_201_CREATED,
        )


class InvitationAcceptView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = InvitationAcceptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invitation = Invitation.objects.select_related(
            'organization',
            'workspace',
        ).filter(
            invite_code=serializer.validated_data['invite_code'],
            status=Invitation.Status.PENDING,
        ).first()
        if invitation is None:
            return Response(
                {'detail': 'Invitation not found or no longer active.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        org_member, _ = OrganizationMember.objects.get_or_create(
            organization=invitation.organization,
            user=request.user,
            defaults={'role': invitation.role},
        )
        if not org_member.is_active:
            org_member.is_active = True
            org_member.save(update_fields=['is_active', 'updated_at'])
        workspace_member, _ = WorkspaceMember.objects.get_or_create(
            workspace=invitation.workspace,
            organization_member=org_member,
            defaults={'role': invitation.role},
        )
        if not workspace_member.is_active:
            workspace_member.is_active = True
            workspace_member.save(update_fields=['is_active', 'updated_at'])
        invitation.status = Invitation.Status.ACCEPTED
        invitation.save(update_fields=['status', 'updated_at'])
        return Response(
            {
                'active_workspace_id': invitation.workspace_id,
                'organizations': _serialize_org_context(request.user),
            }
        )


class WorkspaceMemberDeactivateView(APIView):
    @transaction.atomic
    def post(self, request, member_id):
        membership = WorkspaceMember.objects.select_related(
            'workspace',
            'organization_member',
            'organization_member__organization',
        ).filter(id=member_id).first()
        if membership is None:
            return Response(
                {'detail': 'Workspace member not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        is_admin = WorkspaceMember.objects.filter(
            workspace=membership.workspace,
            organization_member__user=request.user,
            role__in=[
                OrganizationMember.Role.OWNER,
                OrganizationMember.Role.ADMIN,
            ],
            is_active=True,
        ).exists()
        if not is_admin:
            return Response(
                {'detail': 'Admin rights required.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        membership.is_active = False
        membership.save(update_fields=['is_active', 'updated_at'])
        return Response(WorkspaceMemberSerializer(membership).data)
