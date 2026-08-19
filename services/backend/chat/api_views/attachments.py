import hashlib
import os
import tempfile
import uuid
from datetime import timedelta

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.http import FileResponse, Http404, HttpResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import (
    AttachmentChunkReceipt,
    AttachmentUploadSession,
    MessageAttachment,
)
from chat.serializers import (
    AttachmentSessionCompleteSerializer,
    AttachmentSessionCreateSerializer,
    AttachmentUploadSessionSerializer,
    MessageAttachmentSerializer,
)


DEFAULT_ATTACHMENT_SESSION_TTL_DAYS = 7

from .common import (
    get_user_attachment_or_404,
    get_user_attachment_session_or_404,
    get_user_conversation_or_404,
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


def _store_chunk_at_exact_key(storage_key, chunk_bytes, checksum):
    if default_storage.exists(storage_key):
        try:
            if default_storage.size(storage_key) == len(chunk_bytes):
                digest = hashlib.sha256()
                with default_storage.open(storage_key, 'rb') as existing:
                    while True:
                        piece = existing.read(1024 * 1024)
                        if not piece:
                            break
                        digest.update(piece)
                if digest.hexdigest() == checksum:
                    return
        except (OSError, NotImplementedError):
            pass
        default_storage.delete(storage_key)

    saved_key = default_storage.save(storage_key, ContentFile(chunk_bytes))
    if saved_key != storage_key:
        default_storage.delete(saved_key)
        raise RuntimeError('Attachment storage did not preserve the chunk key.')


def _store_final_blob_at_exact_key(storage_key, temp_path):
    # A previous worker may have committed the blob before its database
    # transaction was interrupted. The session row is locked, so replacing
    # this deterministic key is safe and lets the retry rebuild the record.
    if default_storage.exists(storage_key):
        default_storage.delete(storage_key)
    with open(temp_path, 'rb') as completed_blob:
        saved_key = default_storage.save(storage_key, completed_blob)
    if saved_key != storage_key:
        default_storage.delete(saved_key)
        raise RuntimeError('Attachment storage did not preserve the blob key.')


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
        # Serialize chunk receipt creation per session. Without this lock two
        # concurrent retries can both pass the existence check, overwrite the
        # same storage key, and race on the unique receipt constraint.
        session = AttachmentUploadSession.objects.select_for_update().get(
            pk=session.pk,
        )
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
        if session.cipher_version in {'attachment:v2', 'attachment:v3'}:
            plaintext_offset = chunk_index * session.chunk_size
            expected_plaintext_size = min(
                session.chunk_size,
                session.plaintext_size - plaintext_offset,
            )
            expected_ciphertext_size = expected_plaintext_size + 16
            if len(chunk_bytes) != expected_ciphertext_size:
                return Response(
                    {
                        'detail': (
                            'Authenticated attachment chunk must contain the '
                            'plaintext bytes plus a 16-byte AEAD tag.'
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
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
        _store_chunk_at_exact_key(storage_key, chunk_bytes, checksum)
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
        # Completion is idempotent, but it must be serialized with another
        # completion request so two workers cannot create two attachments from
        # one session.
        session = AttachmentUploadSession.objects.select_for_update().get(
            pk=session.pk,
        )
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
        temp_path = None
        try:
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
                return Response(
                    {'detail': 'Ciphertext size mismatch during finalization.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            _store_final_blob_at_exact_key(blob_storage_key, temp_path)
        finally:
            if temp_path is not None:
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
        handle = default_storage.open(attachment.storage_key, 'rb')
        safe_filename = os.path.basename(attachment.filename).replace('"', '_')
        response = FileResponse(
            handle,
            as_attachment=True,
            filename=safe_filename or 'attachment.bin',
            content_type=attachment.mime_type or 'application/octet-stream',
        )
        try:
            response['Content-Length'] = str(default_storage.size(attachment.storage_key))
        except (OSError, NotImplementedError):
            pass
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
