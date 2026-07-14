import hashlib
import json
import base64
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
    CryptoRecoveryAuditEvent,
    HistoricalDeviceKey,
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
    OrganizationSerializer,
    UserSerializer,
    WorkspaceMemberSerializer,
    WorkspaceSerializer,
    WorkspaceSwitchSerializer,
)


User = get_user_model()


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
):
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
        return Response(
            {
                'token': token.key,
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
                'user': UserSerializer(user).data,
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
        return Response({
            'token': token.key,
            'account_id': user.id,
            'device_id': device.device_id,
            'device_status': device.status,
            'profile_fingerprint': device.profile_fingerprint,
            'active_workspace_id': workspace.id,
            'organizations': _serialize_org_context(user),
            'user': UserSerializer(user).data,
        })


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


class CryptoBackupView(APIView):
    """Stores and returns only the user's client-encrypted recovery blob."""

    MAX_BLOB_LENGTH = 5 * 1024 * 1024

    def get(self, request):
        backup = UserCryptoBackup.objects.filter(user=request.user).first()
        if backup is None:
            return Response({'available': False})
        return Response({
            'available': True,
            'version': backup.version,
            'encrypted_blob': backup.encrypted_blob,
            'blob_sha256': backup.blob_sha256,
            'updated_at': backup.updated_at,
        })

    @transaction.atomic
    def put(self, request):
        blob = str(request.data.get('encrypted_blob', '')).strip()
        version = int(request.data.get('version', 0) or 0)
        checksum = str(request.data.get('blob_sha256', '')).strip().lower()
        if not blob or len(blob) > self.MAX_BLOB_LENGTH:
            return Response({'detail': 'Encrypted backup size is invalid.'}, status=413)
        if version <= 0 or len(checksum) != 64:
            return Response({'detail': 'Backup metadata is invalid.'}, status=400)
        expected = hashlib.sha256(blob.encode('utf-8')).hexdigest()
        if checksum != expected:
            return Response({'detail': 'Backup checksum is invalid.'}, status=400)
        backup, _ = UserCryptoBackup.objects.update_or_create(
            user=request.user,
            defaults={
                'version': version,
                'encrypted_blob': blob,
                'blob_sha256': checksum,
            },
        )
        return Response({'available': True, 'version': backup.version, 'updated_at': backup.updated_at})


class AccountRecoveryManifestView(APIView):
    MAX_PAYLOAD_LENGTH = 10 * 1024 * 1024

    def get(self, request):
        if settings.CRYPTO_RECOVERY_REQUIRE_DEVICE_APPROVAL:
            challenge = str(request.query_params.get('approval', '')).strip()
            requester_device_id = str(request.headers.get('X-Device-Id', '')).strip()
            approval = RecoveryDeviceApproval.objects.filter(
                user=request.user,
                challenge=challenge,
                requester_device_id=requester_device_id,
                status=RecoveryDeviceApproval.Status.APPROVED,
                expires_at__gt=timezone.now(),
            ).first()
            if approval is None:
                return Response(
                    {'detail': 'Step-up MFA and approval from another active device are required.', 'code': 'recovery_approval_required'},
                    status=status.HTTP_403_FORBIDDEN,
                )
        manifest = AccountRecoveryManifest.objects.filter(user=request.user).first()
        if manifest is None:
            return Response({'available': False})
        records = []
        provider = get_key_escrow_provider()
        try:
            for record in AccountKeysetEscrowRecord.objects.filter(user=request.user, state='active'):
                records.append({
                    'record_id': record.id,
                    'source_device_id': record.source_device_id,
                    'keyset_id': record.keyset_id,
                    'epoch_id': record.epoch_id,
                    'record_type': record.record_type,
                    'payload': provider.decrypt(
                        account_id=request.user.id,
                        envelope=EscrowEnvelope(
                            encrypted_data_key=record.encrypted_data_key,
                            ciphertext=record.ciphertext,
                            nonce=record.nonce,
                            key_id=record.kms_key_id,
                            encryption_context=record.encryption_context,
                        ),
                    ),
                })
        except (ValueError, PermissionError):
            append_recovery_audit_event(
                user=request.user,
                event_type='kms_decrypt_failure',
                device_id=str(request.headers.get('X-Device-Id', '')),
            )
            return Response({'detail': 'Recovery record is corrupted.'}, status=500)
        append_recovery_audit_event(
            user=request.user,
            event_type='recovery_manifest_read',
            device_id=str(request.headers.get('X-Device-Id', '')),
            metadata={'sequence': manifest.sequence, 'record_count': len(records)},
        )
        return Response({
            'available': True,
            'schema_version': manifest.schema_version,
            'sequence': manifest.sequence,
            'vector_clock': manifest.vector_clock,
            'merkle_root': manifest.merkle_root,
            'records': records,
            'updated_at': manifest.updated_at,
        })

    @transaction.atomic
    def put(self, request):
        return _write_recovery_manifest(request, self.MAX_PAYLOAD_LENGTH)


class CryptoObservabilityView(APIView):
    """Authenticated, tamper-evident operational counters for pilot rollout."""
    _METRICS = {
        'kms_decrypt_failure_count': 'kms_decrypt_failure',
        'manifest_sync_conflict_count': 'manifest_sync_conflict',
        'attachment_decryption_error_total': 'attachment_decryption_error',
    }

    def get(self, request):
        return Response({
            metric: CryptoRecoveryAuditEvent.objects.filter(
                user=request.user,
                event_type=event_type,
            ).count()
            for metric, event_type in self._METRICS.items()
        })

    def post(self, request):
        metric = str(request.data.get('metric', '')).strip()
        event_type = self._METRICS.get(metric)
        if event_type is None:
            return Response({'detail': 'Unknown crypto metric.'}, status=400)
        append_recovery_audit_event(
            user=request.user,
            event_type=event_type,
            device_id=str(request.headers.get('X-Device-Id', '')).strip(),
            metadata={'reported_by': 'client'} if metric == 'attachment_decryption_error_total' else {},
        )
        return Response({metric: 1}, status=status.HTTP_202_ACCEPTED)


def _write_recovery_manifest(request, max_payload_length):
    payload = str(request.data.get('payload', '')).strip()
    schema_version = int(request.data.get('schema_version', 2) or 2)
    expected_sequence = int(request.data.get('expected_sequence', 0) or 0)
    source_device_id = str(request.data.get('source_device_id', '')).strip() or str(request.headers.get('X-Device-Id', '')).strip()
    if not payload or len(payload) > max_payload_length:
        return Response({'detail': 'Account recovery payload is invalid.'}, status=413)
    if not source_device_id:
        return Response({'detail': 'source_device_id is required.'}, status=400)
    checksum = hashlib.sha256(payload.encode('utf-8')).hexdigest()
    manifest, _ = AccountRecoveryManifest.objects.select_for_update().get_or_create(
        user=request.user,
        defaults={
            'schema_version': schema_version,
            'encrypted_payload': '', 'kms_key_id': '', 'kms_key_version': '',
            'payload_sha256': '', 'sequence': 0,
        },
    )
    if expected_sequence != manifest.sequence:
        append_recovery_audit_event(
            user=request.user,
            event_type='manifest_sync_conflict',
            device_id=source_device_id,
            metadata={
                'expected_sequence': expected_sequence,
                'actual_sequence': manifest.sequence,
            },
        )
        return Response({
            'detail': 'Recovery index changed; fetch, merge and retry.',
            'code': 'recovery_manifest_conflict',
            'sequence': manifest.sequence,
            'vector_clock': manifest.vector_clock,
        }, status=status.HTTP_412_PRECONDITION_FAILED)
    envelope = get_key_escrow_provider().encrypt(account_id=request.user.id, plaintext=payload)
    AccountKeysetEscrowRecord.objects.get_or_create(
        user=request.user,
        source_device_id=source_device_id,
        payload_sha256=checksum,
        defaults={
            'encrypted_data_key': envelope.encrypted_data_key,
            'ciphertext': envelope.ciphertext,
            'nonce': envelope.nonce,
            'kms_key_id': envelope.key_id,
            'encryption_context': envelope.encryption_context,
        },
    )
    clock = dict(manifest.vector_clock)
    clock[source_device_id] = int(clock.get(source_device_id, 0)) + 1
    hashes = AccountKeysetEscrowRecord.objects.filter(user=request.user).values_list('payload_sha256', flat=True)
    manifest.schema_version = schema_version
    manifest.sequence += 1
    manifest.vector_clock = clock
    manifest.merkle_root = hashlib.sha256('|'.join(sorted(hashes)).encode()).hexdigest()
    manifest.save(update_fields=['schema_version', 'sequence', 'vector_clock', 'merkle_root', 'updated_at'])
    append_recovery_audit_event(
        user=request.user,
        event_type='recovery_manifest_written',
        device_id=source_device_id,
        metadata={'sequence': manifest.sequence, 'merkle_root': manifest.merkle_root},
    )
    return Response({
        'available': True,
        'schema_version': manifest.schema_version,
        'sequence': manifest.sequence,
        'vector_clock': manifest.vector_clock,
        'merkle_root': manifest.merkle_root,
        'updated_at': manifest.updated_at,
    })


class RecoveryApprovalRequestView(APIView):
    def get(self, request):
        device_id = str(request.headers.get('X-Device-Id', '')).strip()
        approvals = RecoveryDeviceApproval.objects.filter(
            user=request.user,
            status=RecoveryDeviceApproval.Status.PENDING,
            expires_at__gt=timezone.now(),
        ).exclude(requester_device_id=device_id).order_by('-id')
        return Response({'approvals': [{
            'id': item.id,
            'requester_device_id': item.requester_device_id,
            'expires_at': item.expires_at,
        } for item in approvals]})

    @transaction.atomic
    def post(self, request):
        requester_device_id = str(request.data.get('requester_device_id', '')).strip() or str(request.headers.get('X-Device-Id', '')).strip()
        if not requester_device_id:
            return Response({'detail': 'requester_device_id is required.'}, status=400)
        RecoveryDeviceApproval.objects.filter(
            user=request.user,
            requester_device_id=requester_device_id,
            status=RecoveryDeviceApproval.Status.PENDING,
        ).update(status=RecoveryDeviceApproval.Status.EXPIRED)
        approval = RecoveryDeviceApproval.objects.create(
            user=request.user,
            requester_device_id=requester_device_id,
            challenge=uuid4().hex,
            expires_at=timezone.now() + timedelta(minutes=10),
        )
        append_recovery_audit_event(
            user=request.user, event_type='recovery_approval_requested',
            device_id=requester_device_id, metadata={'approval_id': approval.id},
        )
        return Response({'approval_id': approval.id, 'challenge': approval.challenge, 'expires_at': approval.expires_at})


class RecoveryApprovalDecisionView(APIView):
    @transaction.atomic
    def post(self, request, approval_id):
        approver_device_id = str(request.data.get('approver_device_id', '')).strip() or str(request.headers.get('X-Device-Id', '')).strip()
        approval = RecoveryDeviceApproval.objects.select_for_update().filter(user=request.user, id=approval_id).first()
        if approval is None:
            return Response({'detail': 'Recovery approval not found.'}, status=404)
        if approval.expires_at <= timezone.now():
            approval.status = RecoveryDeviceApproval.Status.EXPIRED
            approval.save(update_fields=['status'])
            return Response({'detail': 'Recovery approval expired.'}, status=410)
        if not approver_device_id or approver_device_id == approval.requester_device_id:
            return Response({'detail': 'A different active device must approve recovery.'}, status=400)
        if not UserDevice.objects.filter(user=request.user, device_id=approver_device_id, status=UserDevice.Status.ACTIVE).exists():
            return Response({'detail': 'Approver device is not active.'}, status=403)
        approved = bool(request.data.get('approved', False))
        approval.status = RecoveryDeviceApproval.Status.APPROVED if approved else RecoveryDeviceApproval.Status.DENIED
        approval.approver_device_id = approver_device_id
        approval.approved_at = timezone.now() if approved else None
        approval.save(update_fields=['status', 'approver_device_id', 'approved_at'])
        append_recovery_audit_event(
            user=request.user, event_type='recovery_approval_decided', device_id=approver_device_id,
            metadata={'approval_id': approval.id, 'approved': approved},
        )
        return Response({'approval_id': approval.id, 'status': approval.status})

    def put(self, request, approval_id):
        return Response(
            {'detail': 'Use POST to decide a recovery approval.'},
            status=status.HTTP_405_METHOD_NOT_ALLOWED,
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
