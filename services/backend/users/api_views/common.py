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



def _issue_recovery_access_grant(*, user, device_id):
    """Issue a short-lived bearer that is valid only for one recovery read."""
    raw_token = secrets.token_urlsafe(32)
    RecoveryAccessGrant.objects.filter(
        user=user,
        device_id=device_id,
        used_at__isnull=True,
    ).delete()
    RecoveryAccessGrant.objects.create(
        user=user,
        device_id=device_id,
        token_sha256=hashlib.sha256(raw_token.encode('utf-8')).hexdigest(),
        expires_at=timezone.now()
        + timedelta(seconds=settings.CRYPTO_RECOVERY_GRANT_TTL_SECONDS),
    )
    return raw_token


def _rotate_recovery_device_credential(device):
    raw_token = secrets.token_urlsafe(32)
    device.recovery_credential_sha256 = hashlib.sha256(
        raw_token.encode('utf-8')
    ).hexdigest()
    device.save(update_fields=['recovery_credential_sha256', 'updated_at'])
    return raw_token


def _active_recovery_device(request, *, claimed_device_id=''):
    header_device_id = str(request.headers.get('X-Device-Id', '')).strip()
    if not settings.CRYPTO_RECOVERY_REQUIRE_REGISTERED_DEVICE:
        return header_device_id or claimed_device_id, None
    if not header_device_id:
        return '', Response(
            {'detail': 'A registered device binding is required.', 'code': 'recovery_device_required'},
            status=status.HTTP_403_FORBIDDEN,
        )
    if claimed_device_id and claimed_device_id != header_device_id:
        return '', Response(
            {'detail': 'Recovery device binding mismatch.', 'code': 'recovery_device_mismatch'},
            status=status.HTTP_403_FORBIDDEN,
        )
    raw_credential = str(
        request.headers.get('X-Recovery-Device-Credential', '')
    ).strip()
    if not raw_credential:
        return '', Response(
            {
                'detail': 'Recovery device credential is required.',
                'code': 'recovery_device_credential_required',
            },
            status=status.HTTP_403_FORBIDDEN,
        )
    credential_hash = hashlib.sha256(raw_credential.encode('utf-8')).hexdigest()
    exists = UserDevice.objects.filter(
        user=request.user,
        device_id=header_device_id,
        status=UserDevice.Status.ACTIVE,
        recovery_credential_sha256=credential_hash,
    ).exists()
    if not exists:
        return '', Response(
            {'detail': 'Recovery device is not active.', 'code': 'recovery_device_inactive'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return header_device_id, None


def create_account_for_display_name(display_name):
    return User.objects.create(
        username=f'account_{uuid4().hex[:24]}',
        first_name=display_name,
    )


def _find_user_by_device_signature(*, device_name, platform):
    if not device_name:
        return None
    candidates = list(
        UserDevice.objects.select_related('user')
        .filter(
            device_name=device_name,
            platform=platform,
            status=UserDevice.Status.ACTIVE,
        )
        .order_by('id')[:2]
    )
    if len(candidates) != 1:
        return None
    return candidates[0].user


def _workspace_memberships_for_user(user):
    return WorkspaceMember.objects.select_related(
        'workspace',
        'workspace__organization',
        'organization_member',
    ).filter(
        organization_member__user=user,
        organization_member__is_active=True,
        is_active=True,
    )


def _serialize_org_context(user):
    workspace_memberships = list(_workspace_memberships_for_user(user))
    orgs = []
    roles_by_org = {}
    workspaces_by_org = {}
    seen_org_ids = set()

    for membership in workspace_memberships:
        org = membership.workspace.organization
        if org.id not in seen_org_ids:
            seen_org_ids.add(org.id)
            orgs.append(org)
        roles_by_org[org.id] = membership.organization_member.role
        workspaces_by_org.setdefault(org.id, []).append(membership.workspace)

    return OrganizationSerializer(
        orgs,
        many=True,
        context={
            'roles_by_org': roles_by_org,
            'workspace_memberships_by_org': workspaces_by_org,
        },
    ).data


def _resolve_active_workspace_for_user(user, requested_workspace_id=''):
    memberships = _workspace_memberships_for_user(user)
    if requested_workspace_id and requested_workspace_id.isdigit():
        membership = memberships.filter(workspace_id=int(requested_workspace_id)).first()
        if membership is not None:
            return membership.workspace
    default_membership = memberships.order_by('-workspace__is_default', 'workspace_id').first()
    return None if default_membership is None else default_membership.workspace


def _get_request_active_workspace(request):
    workspace = _resolve_active_workspace_for_user(
        request.user,
        request.headers.get('X-Workspace-Id', '').strip(),
    )
    if workspace is None:
        return None, Response(
            {'detail': 'Active workspace was not found for this user.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return workspace, None


def _ensure_default_workspace_membership(user):
    org, _ = _safe_get_or_create(
        Organization,
        slug='default-org',
        defaults={
            'name': 'Default Organization',
            'created_by': user,
        },
    )
    workspace, _ = _safe_get_or_create(
        Workspace,
        organization=org,
        slug='main-workspace',
        defaults={
            'name': 'Main Workspace',
            'is_default': True,
            'policy_flags': {
                'attachments_enabled': True,
                'typing_presence_enabled': True,
            },
        },
    )
    org_member, created = _safe_get_or_create(
        OrganizationMember,
        organization=org,
        user=user,
        defaults={
            'role': OrganizationMember.Role.OWNER,
        },
    )
    if not created and not org_member.is_active:
        org_member.is_active = True
        org_member.save(update_fields=['is_active', 'updated_at'])
    workspace_member, created = _safe_get_or_create(
        WorkspaceMember,
        workspace=workspace,
        organization_member=org_member,
        defaults={
            'role': org_member.role,
        },
    )
    if not created and not workspace_member.is_active:
        workspace_member.is_active = True
        workspace_member.save(update_fields=['is_active', 'updated_at'])
    return org, workspace


def _safe_get_or_create(model, defaults=None, **lookup):
    try:
        return model.objects.get_or_create(defaults=defaults or {}, **lookup)
    except IntegrityError:
        return model.objects.get(**lookup), False


def upsert_user_device(
    *,
    user,
    device_id,
    device_name='',
    platform='',
    identity_public_key='',
    key_algorithm='',
    pqc_public_key='',
    pqc_algorithm='',
    pqc_signing_public_key='',
    pqc_signing_algorithm='',
    supported_protocols=None,
):
    supported_protocols = normalize_supported_protocols(supported_protocols)
    profile_fingerprint = build_device_profile_fingerprint(
        device_id=device_id,
        identity_public_key=identity_public_key,
        key_algorithm=key_algorithm,
        pqc_public_key=pqc_public_key,
        pqc_algorithm=pqc_algorithm,
        pqc_signing_public_key=pqc_signing_public_key,
        pqc_signing_algorithm=pqc_signing_algorithm,
    )
    device, device_created = UserDevice.objects.get_or_create(
        device_id=device_id,
        defaults={
            'user': user,
            'device_name': device_name,
            'platform': platform,
            'identity_public_key': identity_public_key,
            'key_algorithm': key_algorithm,
            'pqc_public_key': pqc_public_key,
            'pqc_algorithm': pqc_algorithm,
            'pqc_signing_public_key': pqc_signing_public_key,
            'pqc_signing_algorithm': pqc_signing_algorithm,
            'supported_protocols': supported_protocols,
            'status': UserDevice.Status.ACTIVE,
            'profile_fingerprint': profile_fingerprint,
            'last_seen_at': timezone.now(),
        },
    )
    if not device_created and device.user_id != user.id:
        return None, Response(
            {
                'detail': 'This device is already linked to another username.',
                'code': 'device_owner_mismatch',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not device_created:
        if device.status != UserDevice.Status.ACTIVE:
            return None, Response(
                {
                    'detail': 'This device is no longer active.',
                    'code': 'device_revoked',
                },
                status=status.HTTP_409_CONFLICT,
            )

        if device.profile_fingerprint and device.profile_fingerprint != profile_fingerprint:
            HistoricalDeviceKey.objects.get_or_create(
                user=device.user,
                device_id=device.device_id,
                profile_fingerprint=device.profile_fingerprint,
                defaults={
                    'identity_public_key': device.identity_public_key,
                    'key_algorithm': device.key_algorithm,
                    'pqc_public_key': device.pqc_public_key,
                    'pqc_algorithm': device.pqc_algorithm,
                    'pqc_signing_public_key': device.pqc_signing_public_key,
                    'pqc_signing_algorithm': device.pqc_signing_algorithm,
                },
            )
            return None, Response(
                {
                    'detail': 'Device crypto profile changed; re-enrollment is required.',
                    'code': 'device_profile_mismatch',
                    'profile_fingerprint': device.profile_fingerprint,
                },
                status=status.HTTP_409_CONFLICT,
            )

        updated_fields = ['last_seen_at']
        device.last_seen_at = timezone.now()
        if device.device_name != device_name:
            device.device_name = device_name
            updated_fields.append('device_name')
        if device.platform != platform:
            device.platform = platform
            updated_fields.append('platform')
        if device.identity_public_key != identity_public_key:
            device.identity_public_key = identity_public_key
            updated_fields.append('identity_public_key')
        if device.key_algorithm != key_algorithm:
            device.key_algorithm = key_algorithm
            updated_fields.append('key_algorithm')
        if device.pqc_public_key != pqc_public_key:
            device.pqc_public_key = pqc_public_key
            updated_fields.append('pqc_public_key')
        if device.pqc_algorithm != pqc_algorithm:
            device.pqc_algorithm = pqc_algorithm
            updated_fields.append('pqc_algorithm')
        if device.pqc_signing_public_key != pqc_signing_public_key:
            device.pqc_signing_public_key = pqc_signing_public_key
            updated_fields.append('pqc_signing_public_key')
        if device.pqc_signing_algorithm != pqc_signing_algorithm:
            device.pqc_signing_algorithm = pqc_signing_algorithm
            updated_fields.append('pqc_signing_algorithm')
        normalized_device_protocols = normalize_supported_protocols(
            device.supported_protocols
        )
        if normalized_device_protocols != supported_protocols:
            device.supported_protocols = supported_protocols
            updated_fields.append('supported_protocols')
        if not device.profile_fingerprint:
            device.profile_fingerprint = profile_fingerprint
            updated_fields.append('profile_fingerprint')
        if updated_fields:
            device.save(update_fields=updated_fields + ['updated_at'])

    return device, None


def build_device_profile_fingerprint(
    *,
    device_id,
    identity_public_key,
    key_algorithm,
    pqc_public_key,
    pqc_algorithm,
    pqc_signing_public_key,
    pqc_signing_algorithm,
):
    payload = '|'.join(
        [
            device_id,
            key_algorithm,
            identity_public_key,
            pqc_algorithm,
            pqc_public_key,
            pqc_signing_algorithm,
            pqc_signing_public_key,
        ]
    )
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()
