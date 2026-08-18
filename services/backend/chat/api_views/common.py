import hashlib
import logging
import os
import tempfile
import uuid
from datetime import timedelta

from django.contrib.auth import get_user_model
from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from django.db import transaction
from django.db.models import Q
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
    MessageReceipt,
    MessageReaction,
    MessageAttachment,
)
from chat.serializers import (
    AttachmentUploadSerializer,
    AttachmentSessionCompleteSerializer,
    AttachmentSessionCreateSerializer,
    AttachmentUploadSessionSerializer,
    ConversationSerializer,
    GROUP_ENVELOPE_ALGORITHM,
    ConversationKeyEnvelopeSerializer,
    ConversationKeyEnvelopeSyncSerializer,
    MessageCreateSerializer,
    MessageAttachmentSerializer,
    MessageSerializer,
    MessageReactionSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)
from chat.protocols import get_protocol_capabilities
from chat.protocols import v2 as v2_protocol
from users.models import UserDevice, WorkspaceMember
from users.serializers import (
    is_valid_ml_kem_768_public_key,
    normalize_supported_protocols,
)


User = get_user_model()
DEFAULT_ATTACHMENT_SESSION_TTL_DAYS = 7
logger = logging.getLogger(__name__)



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
    try:
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
    except Exception:
        # Realtime delivery is auxiliary. The committed HTTP write remains the
        # source of truth and clients recover through incremental polling.
        logger.exception(
            'Failed to publish workspace event',
            extra={'workspace_id': workspace_id, 'event_type': event_type},
        )


def publish_workspace_event_on_commit(workspace_id, event_type, payload):
    transaction.on_commit(
        lambda: publish_workspace_event(workspace_id, event_type, payload)
    )


