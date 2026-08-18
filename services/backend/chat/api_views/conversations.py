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



from .common import get_request_workspace_or_403

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
        search = request.query_params.get('search', '').strip()
        if search:
            conversations = conversations.filter(
                Q(title__icontains=search)
                | Q(participants__username__icontains=search)
                | Q(participants__first_name__icontains=search)
            ).distinct()
        try:
            offset = max(0, int(request.query_params.get('offset', '0')))
            limit = min(100, max(1, int(request.query_params.get('limit', '50'))))
        except ValueError:
            return Response({'detail': 'offset and limit must be integers.'}, status=400)
        page = list(conversations[offset:offset + limit + 1])
        has_more = len(page) > limit
        page = page[:limit]
        response = Response(
            ConversationSerializer(
                page,
                many=True,
                context={'request': request},
            ).data
        )
        response['X-Has-More'] = 'true' if has_more else 'false'
        response['X-Next-Offset'] = str(offset + limit if has_more else '')
        return response


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
        return Response(
            ConversationSerializer(
                conversation,
                context={'request': request},
            ).data
        )


