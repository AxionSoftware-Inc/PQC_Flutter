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



class CryptoProtocolCapabilitiesView(APIView):
    """Public, immutable writer capabilities for the deployed API."""

    authentication_classes = []
    permission_classes = []

    def get(self, request):
        return Response(get_protocol_capabilities())


