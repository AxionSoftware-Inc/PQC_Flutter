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



from .common import _active_recovery_device

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

    @transaction.atomic
    def get(self, request):
        requester_device_id, error_response = _active_recovery_device(request)
        if error_response is not None:
            return error_response
        manifest = AccountRecoveryManifest.objects.filter(user=request.user).first()
        if manifest is None:
            return Response({'available': False})

        if str(request.query_params.get('metadata_only', '')).lower() == 'true':
            return Response({
                'available': True,
                'schema_version': manifest.schema_version,
                'sequence': manifest.sequence,
                'vector_clock': manifest.vector_clock,
                'merkle_root': manifest.merkle_root,
                'record_hashes': list(
                    AccountKeysetEscrowRecord.objects.filter(
                        user=request.user,
                        state='active',
                    ).values_list('payload_sha256', flat=True)
                ),
                'updated_at': manifest.updated_at,
            })

        challenge = str(request.query_params.get('approval', '')).strip()
        approval = None
        access_grant = None
        if settings.CRYPTO_RECOVERY_REQUIRE_DEVICE_APPROVAL:
            approval = RecoveryDeviceApproval.objects.filter(
                user=request.user,
                challenge=challenge,
                requester_device_id=requester_device_id,
                status=RecoveryDeviceApproval.Status.APPROVED,
                expires_at__gt=timezone.now(),
            ).first()
            raw_grant = str(request.headers.get('X-Recovery-Grant', '')).strip()
            if raw_grant:
                access_grant = RecoveryAccessGrant.objects.select_for_update().filter(
                    user=request.user,
                    device_id=requester_device_id,
                    token_sha256=hashlib.sha256(raw_grant.encode('utf-8')).hexdigest(),
                    used_at__isnull=True,
                    expires_at__gt=timezone.now(),
                ).first()
            if approval is None and access_grant is None:
                return Response(
                    {
                        'detail': 'Fresh Google verification or approval from another active device is required.',
                        'code': 'recovery_approval_required',
                    },
                    status=status.HTTP_403_FORBIDDEN,
                )
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
        if approval is not None:
            approval.status = RecoveryDeviceApproval.Status.USED
            approval.save(update_fields=['status'])
        if access_grant is not None:
            access_grant.used_at = timezone.now()
            access_grant.save(update_fields=['used_at'])
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
        source_device_id = str(request.data.get('source_device_id', '')).strip()
        _, error_response = _active_recovery_device(
            request,
            claimed_device_id=source_device_id,
        )
        if error_response is not None:
            return error_response
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
    try:
        envelope = get_key_escrow_provider().encrypt(
            account_id=request.user.id,
            plaintext=payload,
        )
    except Exception:
        # Escrow availability is an operational retry condition, not an
        # application crash.  Roll back the manifest row created above so a
        # retry sees the same sequence and cannot mistake a partial write for
        # a successful recovery snapshot.
        logger.exception('Recovery escrow write failed for account %s', request.user.id)
        transaction.set_rollback(True)
        return Response(
            {
                'detail': 'Recovery storage is temporarily unavailable. Retry safely.',
                'code': 'recovery_escrow_unavailable',
                'retryable': True,
            },
            status=status.HTTP_503_SERVICE_UNAVAILABLE,
        )
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
        device_id, error_response = _active_recovery_device(request)
        if error_response is not None:
            return error_response
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
        claimed_device_id = str(request.data.get('requester_device_id', '')).strip()
        requester_device_id, error_response = _active_recovery_device(
            request,
            claimed_device_id=claimed_device_id,
        )
        if error_response is not None:
            return error_response
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
        claimed_device_id = str(request.data.get('approver_device_id', '')).strip()
        approver_device_id, error_response = _active_recovery_device(
            request,
            claimed_device_id=claimed_device_id,
        )
        if error_response is not None:
            return error_response
        approval = RecoveryDeviceApproval.objects.select_for_update().filter(user=request.user, id=approval_id).first()
        if approval is None:
            return Response({'detail': 'Recovery approval not found.'}, status=404)
        if approval.status != RecoveryDeviceApproval.Status.PENDING:
            return Response(
                {'detail': 'Recovery approval is no longer pending.'},
                status=status.HTTP_409_CONFLICT,
            )
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


