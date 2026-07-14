import hashlib
import os
import tempfile
import uuid
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.http import Http404, HttpResponse
from django.utils import timezone
from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer
from rest_framework import generics, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import (
    AttachmentChunkReceipt,
    AttachmentUploadSession,
    Conversation,
    ConversationCryptoEpoch,
    Message,
    MessageAttachment,
)
from chat.serializers import (
    AttachmentUploadSerializer,
    AttachmentSessionCompleteSerializer,
    AttachmentSessionCreateSerializer,
    AttachmentUploadSessionSerializer,
    CRYPTO_PROTOCOL_CAPABILITIES,
    ConversationSerializer,
    GROUP_ENVELOPE_ALGORITHM,
    ConversationKeyEnvelopeSerializer,
    ConversationKeyEnvelopeSyncSerializer,
    MessageCreateSerializer,
    MessageAttachmentSerializer,
    MessageSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)
from users.models import UserDevice, WorkspaceMember


User = get_user_model()
DEFAULT_ATTACHMENT_SESSION_TTL_DAYS = 7


class CryptoProtocolCapabilitiesView(APIView):
    """Public, immutable writer capabilities for the deployed API."""

    authentication_classes = []
    permission_classes = []

    def get(self, request):
        return Response(CRYPTO_PROTOCOL_CAPABILITIES)


def get_user_conversation_or_404(request, conversation_id):
    workspace, error_response = get_request_workspace_or_403(request)
    if error_response is not None:
        raise PermissionDenied(error_response.data['detail'])
    return generics.get_object_or_404(
        Conversation.objects.filter(
            participants=request.user,
            workspace=workspace,
            workspace__members__organization_member__user=request.user,
            workspace__members__organization_member__is_active=True,
            workspace__members__is_active=True,
        ).distinct(),
        pk=conversation_id,
    )


def get_request_device_or_400(request):
    device_id = request.headers.get('X-Device-Id', '').strip()
    if not device_id:
        return None, Response(
            {'detail': 'X-Device-Id header is required.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    device = UserDevice.objects.filter(
        user=request.user,
        device_id=device_id,
        status=UserDevice.Status.ACTIVE,
    ).first()
    if device is None:
        return None, Response(
            {'detail': 'Current device is not registered for this user.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    return device, None


def get_request_workspace_or_403(request):
    workspace_id = request.headers.get('X-Workspace-Id', '').strip()
    memberships = WorkspaceMember.objects.select_related(
        'workspace',
        'organization_member',
    ).filter(
        organization_member__user=request.user,
        organization_member__is_active=True,
        is_active=True,
    )
    if workspace_id.isdigit():
        membership = memberships.filter(workspace_id=int(workspace_id)).first()
        if membership is not None:
            return membership.workspace, None
    membership = memberships.order_by('-workspace__is_default', 'workspace_id').first()
    if membership is None:
        return None, Response(
            {'detail': 'No active workspace available.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return membership.workspace, None


def get_user_attachment_or_404(request, attachment_id):
    workspace, error_response = get_request_workspace_or_403(request)
    if error_response is not None:
        raise PermissionDenied(error_response.data['detail'])
    return generics.get_object_or_404(
        MessageAttachment.objects.filter(
            conversation__participants=request.user,
            workspace=workspace,
            workspace__members__organization_member__user=request.user,
            workspace__members__organization_member__is_active=True,
            workspace__members__is_active=True,
        ).distinct(),
        pk=attachment_id,
    )


def get_user_attachment_session_or_404(request, session_id):
    workspace, error_response = get_request_workspace_or_403(request)
    if error_response is not None:
        raise PermissionDenied(error_response.data['detail'])
    return generics.get_object_or_404(
        AttachmentUploadSession.objects.filter(
            session_id=session_id,
            conversation__participants=request.user,
            workspace=workspace,
            uploaded_by=request.user,
            workspace__members__organization_member__user=request.user,
            workspace__members__organization_member__is_active=True,
            workspace__members__is_active=True,
        ).distinct(),
    )


def publish_workspace_event(workspace_id, event_type, payload):
    channel_layer = get_channel_layer()
    if channel_layer is None:
        return
    async_to_sync(channel_layer.group_send)(
        f'workspace_{workspace_id}',
        {
            'type': 'chat.event',
            'event': event_type,
            'payload': payload,
        },
    )


class ConversationListView(APIView):
    def get(self, request):
        updated_after = request.query_params.get('updated_after', '').strip()
        workspace, error_response = get_request_workspace_or_403(request)
        if error_response is not None:
            return error_response
        conversations = (
            Conversation.objects.filter(
                participants=request.user,
                workspace=workspace,
            )
            .prefetch_related('participants', 'messages')
            .distinct()
        )
        if updated_after:
            conversations = conversations.filter(updated_at__gt=updated_after)
        return Response(ConversationSerializer(conversations, many=True).data)


class PrivateConversationView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = PrivateConversationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        other_user = generics.get_object_or_404(
            User,
            pk=serializer.validated_data['other_user_id'],
        )
        if other_user == request.user:
            return Response(
                {'detail': 'Cannot create private chat with yourself.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        workspace, error_response = get_request_workspace_or_403(request)
        if error_response is not None:
            return error_response

        conversation, _ = get_or_create_private_conversation(
            request.user,
            other_user,
            workspace,
        )
        return Response(ConversationSerializer(conversation).data)


class MessageListCreateView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        after_id = request.query_params.get('after_id', '').strip()
        messages = conversation.messages.select_related('sender').prefetch_related('attachments').all()
        if after_id.isdigit():
            messages = messages.filter(id__gt=int(after_id))
        return Response(MessageSerializer(messages, many=True).data)

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        serializer = MessageCreateSerializer(
            data=request.data,
            context={'conversation': conversation},
        )
        serializer.is_valid(raise_exception=True)

        if not conversation.participants.filter(id=request.user.id).exists():
            raise PermissionDenied('Not a participant of this conversation.')

        client_message_id = serializer.validated_data['client_message_id'].strip()
        if client_message_id:
            existing = Message.objects.filter(
                conversation=conversation,
                sender=request.user,
                client_message_id=client_message_id,
            ).select_related('sender').first()
            if existing is not None:
                return Response(MessageSerializer(existing).data)

        message = Message.objects.create(
            conversation=conversation,
            sender=request.user,
            body=serializer.validated_data['body'].strip(),
            client_message_id=client_message_id,
            message_type=serializer.validated_data['message_type'],
        )
        attachments = MessageAttachment.objects.filter(
            id__in=serializer.validated_data['attachment_ids'],
            conversation=conversation,
            workspace=conversation.workspace,
            uploaded_by=request.user,
            message__isnull=True,
        )
        attachment_count = attachments.count()
        if attachment_count:
            attachments.update(message=message)
            message.attachment_count = attachment_count
            message.save(update_fields=['attachment_count'])
        conversation.save(update_fields=['updated_at'])
        serialized = MessageSerializer(message).data
        publish_workspace_event(
            conversation.workspace_id,
            'message.created',
            serialized,
        )
        publish_workspace_event(
            conversation.workspace_id,
            'conversation.updated',
            {
                'id': conversation.id,
                'workspace_id': conversation.workspace_id,
                'updated_at': conversation.updated_at.isoformat(),
            },
        )
        return Response(
            serialized,
            status=status.HTTP_201_CREATED,
        )


class ConversationKeyEnvelopeView(APIView):
    def get(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        device, error_response = get_request_device_or_400(request)
        if error_response is not None:
            return error_response

        envelopes = conversation.key_envelopes.filter(
            target_device=device,
        ).select_related('target_device', 'sender_device')
        return Response(
            ConversationKeyEnvelopeSerializer(envelopes, many=True).data
        )

    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        sender_device, error_response = get_request_device_or_400(request)
        if error_response is not None:
            return error_response

        serializer = ConversationKeyEnvelopeSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        participant_user_ids = set(
            conversation.participants.values_list('id', flat=True)
        )
        expected_target_ids = set(
            UserDevice.objects.filter(
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
                pqc_algorithm='ml-kem-768',
                pqc_signing_algorithm='ml-dsa-65',
            )
            .exclude(pqc_public_key='')
            .exclude(pqc_signing_public_key='')
            .values_list('device_id', flat=True)
        )
        submitted_target_ids = []
        for item in serializer.validated_data['envelopes']:
            submitted_target_ids.append(item['target_device_id'])
            target_device = UserDevice.objects.filter(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
            ).first()
            if target_device is None:
                return Response(
                    {
                        'detail': f"Target device '{item['target_device_id']}' is not part of this conversation.",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

        submitted_target_id_set = set(submitted_target_ids)

        if len(submitted_target_ids) != len(submitted_target_id_set):
            return Response(
                {'detail': 'Duplicate target_device_id entries are not allowed.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        if expected_target_ids != submitted_target_id_set:
            missing_ids = sorted(expected_target_ids - submitted_target_id_set)
            extra_ids = sorted(submitted_target_id_set - expected_target_ids)
            parts = []
            if missing_ids:
                parts.append(f"missing devices: {', '.join(missing_ids)}")
            if extra_ids:
                parts.append(f"unexpected devices: {', '.join(extra_ids)}")
            return Response(
                {
                    'detail': 'Envelope set must exactly match the registered group devices.',
                    'mismatch': parts,
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        if serializer.validated_data['algorithm'] != GROUP_ENVELOPE_ALGORITHM:
            return Response(
                {
                    'detail': 'Only group-ml-kem-768-aesgcm-v2 is accepted.',
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        saved = []
        for item in serializer.validated_data['envelopes']:
            target_device = UserDevice.objects.get(
                device_id=item['target_device_id'],
                user_id__in=participant_user_ids,
                status=UserDevice.Status.ACTIVE,
            )
            envelope, _ = conversation.key_envelopes.update_or_create(
                target_device=target_device,
                key_id=serializer.validated_data['key_id'],
                defaults={
                    'sender_device': sender_device,
                    'algorithm': serializer.validated_data['algorithm'],
                    'wrapped_key': item['wrapped_key'],
                },
            )
            saved.append(envelope)

        ConversationCryptoEpoch.objects.filter(
            conversation=conversation,
            state__in=[
                ConversationCryptoEpoch.State.ACTIVE,
                ConversationCryptoEpoch.State.PENDING,
            ],
        ).exclude(epoch_id=serializer.validated_data['key_id']).update(
            state=ConversationCryptoEpoch.State.CLOSED,
        )
        ConversationCryptoEpoch.objects.update_or_create(
            conversation=conversation,
            epoch_id=serializer.validated_data['key_id'],
            defaults={
                'state': ConversationCryptoEpoch.State.ACTIVE,
                'reason': '',
                'activated_at': timezone.now(),
            },
        )

        return Response(
            ConversationKeyEnvelopeSerializer(saved, many=True).data,
            status=status.HTTP_201_CREATED,
        )


class AttachmentUploadView(APIView):
    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        serializer = AttachmentUploadSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        uploaded = serializer.validated_data['file']
        storage_key = default_storage.save(
            f'attachments/{conversation.workspace_id}/{conversation.id}/{uploaded.name}',
            uploaded,
        )
        attachment = MessageAttachment.objects.create(
            conversation=conversation,
            workspace=conversation.workspace,
            uploaded_by=request.user,
            filename=uploaded.name,
            mime_type=getattr(uploaded, 'content_type', 'application/octet-stream'),
            size_bytes=uploaded.size,
            storage_key=storage_key,
        )
        return Response(
            MessageAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )


def _chunk_storage_key(session, chunk_index):
    return (
        f'attachment_sessions/{session.workspace_id}/'
        f'{session.conversation_id}/{session.session_id}/chunks/{chunk_index:08d}.bin'
    )


def _final_blob_storage_key(session):
    return (
        f'attachments/{session.workspace_id}/'
        f'{session.conversation_id}/{session.session_id}.blob'
    )


def _mark_session_expired_if_needed(session):
    if session.status == AttachmentUploadSession.Status.COMPLETED:
        return False
    if session.is_expired and session.status != AttachmentUploadSession.Status.EXPIRED:
        session.status = AttachmentUploadSession.Status.EXPIRED
        session.save(update_fields=['status', 'updated_at'])
        return True
    return session.status == AttachmentUploadSession.Status.EXPIRED


class AttachmentSessionCreateView(APIView):
    @transaction.atomic
    def post(self, request, conversation_id):
        conversation = get_user_conversation_or_404(request, conversation_id)
        serializer = AttachmentSessionCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        payload = serializer.validated_data
        session = AttachmentUploadSession.objects.create(
            session_id=uuid.uuid4().hex,
            conversation=conversation,
            workspace=conversation.workspace,
            uploaded_by=request.user,
            filename=payload['filename'],
            mime_type=payload['mime_type'],
            cipher_version=payload['cipher_version'],
            plaintext_size=payload['plaintext_size'],
            ciphertext_size=payload['ciphertext_size'],
            chunk_size=payload['chunk_size'],
            total_chunks=payload['total_chunks'],
            plaintext_sha256=payload['plaintext_sha256'],
            manifest_sha256=payload['manifest_sha256'],
            file_key_wrap=payload['file_key_wrap'],
            conversation_epoch_id=payload['conversation_epoch_id'],
            recovery_manifest_sequence=payload['recovery_manifest_sequence'],
            status=AttachmentUploadSession.Status.PENDING,
            expires_at=timezone.now() + timedelta(days=DEFAULT_ATTACHMENT_SESSION_TTL_DAYS),
        )
        return Response(
            AttachmentUploadSessionSerializer(session).data,
            status=status.HTTP_201_CREATED,
        )


class AttachmentSessionDetailView(APIView):
    def get(self, request, session_id):
        session = get_user_attachment_session_or_404(request, session_id)
        _mark_session_expired_if_needed(session)
        session.refresh_from_db()
        return Response(AttachmentUploadSessionSerializer(session).data)


class AttachmentSessionChunkView(APIView):
    @transaction.atomic
    def put(self, request, session_id, chunk_index):
        session = get_user_attachment_session_or_404(request, session_id)
        if _mark_session_expired_if_needed(session):
            return Response(
                {'detail': 'Attachment upload session expired.'},
                status=status.HTTP_410_GONE,
            )
        if session.status == AttachmentUploadSession.Status.COMPLETED:
            return Response(
                {'detail': 'Attachment upload session already completed.'},
                status=status.HTTP_409_CONFLICT,
            )
        if chunk_index < 0 or chunk_index >= session.total_chunks:
            return Response(
                {'detail': 'Chunk index out of range.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        chunk_bytes = request.body or b''
        expected_size = request.headers.get('X-Chunk-Size', '').strip()
        checksum = request.headers.get('X-Chunk-Sha256', '').strip().lower()
        if not checksum:
            return Response(
                {'detail': 'X-Chunk-Sha256 header is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if expected_size and expected_size.isdigit() and int(expected_size) != len(chunk_bytes):
            return Response(
                {'detail': 'Chunk size does not match X-Chunk-Size.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        actual_checksum = hashlib.sha256(chunk_bytes).hexdigest()
        if actual_checksum != checksum:
            return Response(
                {'detail': 'Chunk checksum mismatch.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing = session.chunk_receipts.filter(chunk_index=chunk_index).first()
        if existing is not None:
            if existing.ciphertext_sha256 != checksum or existing.chunk_size != len(chunk_bytes):
                return Response(
                    {'detail': 'Chunk already exists with different content.'},
                    status=status.HTTP_409_CONFLICT,
                )
            return Response(
                {'accepted': True, 'duplicate': True},
                status=status.HTTP_200_OK,
            )

        storage_key = _chunk_storage_key(session, chunk_index)
        default_storage.save(storage_key, ContentFile(chunk_bytes))
        AttachmentChunkReceipt.objects.create(
            session=session,
            chunk_index=chunk_index,
            chunk_size=len(chunk_bytes),
            ciphertext_sha256=checksum,
            storage_key=storage_key,
        )
        if session.status == AttachmentUploadSession.Status.PENDING:
            session.status = AttachmentUploadSession.Status.UPLOADING
            session.save(update_fields=['status', 'updated_at'])
        return Response(
            {'accepted': True, 'duplicate': False},
            status=status.HTTP_201_CREATED,
        )


class AttachmentSessionCompleteView(APIView):
    @transaction.atomic
    def post(self, request, session_id):
        session = get_user_attachment_session_or_404(request, session_id)
        if _mark_session_expired_if_needed(session):
            return Response(
                {'detail': 'Attachment upload session expired.'},
                status=status.HTTP_410_GONE,
            )
        serializer = AttachmentSessionCompleteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if session.completed_attachment is not None:
            return Response(
                MessageAttachmentSerializer(session.completed_attachment).data,
                status=status.HTTP_200_OK,
            )
        if session.chunk_receipts.count() != session.total_chunks:
            return Response(
                {'detail': 'Missing chunks. Upload is not complete yet.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        manifest_sha256 = serializer.validated_data.get('manifest_sha256', '').strip()
        if manifest_sha256 and manifest_sha256 != session.manifest_sha256:
            return Response(
                {'detail': 'Manifest checksum mismatch.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        blob_storage_key = _final_blob_storage_key(session)
        total_written = 0
        with tempfile.NamedTemporaryFile(delete=False) as temp_handle:
            temp_path = temp_handle.name
            for receipt in session.chunk_receipts.order_by('chunk_index'):
                with default_storage.open(receipt.storage_key, 'rb') as source:
                    while True:
                        chunk = source.read(1024 * 1024)
                        if not chunk:
                            break
                        temp_handle.write(chunk)
                        total_written += len(chunk)
        if total_written != session.ciphertext_size:
            try:
                os.unlink(temp_path)
            except OSError:
                pass
            return Response(
                {'detail': 'Ciphertext size mismatch during finalization.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        with open(temp_path, 'rb') as completed_blob:
            default_storage.save(blob_storage_key, completed_blob)
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        attachment = MessageAttachment.objects.create(
            conversation=session.conversation,
            workspace=session.workspace,
            uploaded_by=session.uploaded_by,
            filename=session.filename,
            mime_type=session.mime_type,
            size_bytes=session.plaintext_size,
            storage_key=blob_storage_key,
            cipher_version=session.cipher_version,
            plaintext_size=session.plaintext_size,
            ciphertext_size=session.ciphertext_size,
            chunk_size=session.chunk_size,
            plaintext_sha256=session.plaintext_sha256,
            manifest_sha256=session.manifest_sha256,
            file_key_wrap=session.file_key_wrap,
            conversation_epoch_id=session.conversation_epoch_id,
            recovery_manifest_sequence=session.recovery_manifest_sequence,
        )
        session.completed_attachment = attachment
        session.blob_storage_key = blob_storage_key
        session.status = AttachmentUploadSession.Status.COMPLETED
        session.save(
            update_fields=[
                'completed_attachment',
                'blob_storage_key',
                'status',
                'updated_at',
            ]
        )
        return Response(
            MessageAttachmentSerializer(attachment).data,
            status=status.HTTP_201_CREATED,
        )


class AttachmentDownloadDescriptorView(APIView):
    def get(self, request, attachment_id):
        attachment = get_user_attachment_or_404(request, attachment_id)
        total_chunks = 0
        if attachment.chunk_size > 0 and attachment.plaintext_size > 0:
            total_chunks = (attachment.plaintext_size + attachment.chunk_size - 1) // attachment.chunk_size
        payload = MessageAttachmentSerializer(attachment).data
        payload['download'] = {
            'chunk_size': attachment.chunk_size,
            'ciphertext_size': attachment.ciphertext_size,
            'total_chunks': total_chunks,
        }
        return Response(payload)


class AttachmentDownloadFileView(APIView):
    """Simple whole-file download for normal chat attachments.

    Resumable chunk endpoints remain for legacy sessions, but regular chat
    attachments use one binary response so history polling is never coupled
    to a transfer state machine.
    """

    def get(self, request, attachment_id):
        attachment = get_user_attachment_or_404(request, attachment_id)
        with default_storage.open(attachment.storage_key, 'rb') as handle:
            data = handle.read()
        response = HttpResponse(
            data,
            content_type=attachment.mime_type or 'application/octet-stream',
        )
        response['Content-Length'] = str(len(data))
        safe_filename = attachment.filename.replace('"', '_')
        response['Content-Disposition'] = f'attachment; filename="{safe_filename}"'
        return response


class AttachmentDownloadChunkView(APIView):
    def get(self, request, attachment_id, chunk_index):
        attachment = get_user_attachment_or_404(request, attachment_id)
        if (
            attachment.chunk_size <= 0
            or attachment.ciphertext_size <= 0
            or attachment.plaintext_size <= 0
        ):
            return Response(
                {'detail': 'Attachment is not chunk-downloadable.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        total_chunks = (attachment.plaintext_size + attachment.chunk_size - 1) // attachment.chunk_size
        if chunk_index < 0 or chunk_index >= total_chunks:
            raise Http404('Chunk index out of range.')
        per_chunk_overhead = 16
        if chunk_index < total_chunks - 1:
            start = chunk_index * (attachment.chunk_size + per_chunk_overhead)
            end = start + attachment.chunk_size + per_chunk_overhead
        else:
            consumed_plaintext = attachment.chunk_size * (total_chunks - 1)
            last_plaintext = max(attachment.plaintext_size - consumed_plaintext, 0)
            start = (attachment.chunk_size + per_chunk_overhead) * (total_chunks - 1)
            end = start + last_plaintext + per_chunk_overhead
        length = end - start
        with default_storage.open(attachment.storage_key, 'rb') as handle:
            handle.seek(start)
            data = handle.read(length)
        response = HttpResponse(data, content_type='application/octet-stream')
        response['Content-Length'] = str(len(data))
        response['X-Chunk-Index'] = str(chunk_index)
        response['X-Chunk-Count'] = str(total_chunks)
        response['X-Attachment-Id'] = str(attachment.id)
        return response
