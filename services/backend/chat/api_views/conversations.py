from django.contrib.auth import get_user_model
from django.db import transaction
from django.db.models import Count, IntegerField, OuterRef, Prefetch, Q, Subquery, Value
from django.db.models.functions import Coalesce
from django.utils.dateparse import parse_datetime
from django.utils import timezone
from rest_framework import generics, status
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, Message
from users.models import WorkspaceMember
from chat.serializers import (
    ConversationSerializer,
    PrivateConversationSerializer,
    get_or_create_private_conversation,
)


User = get_user_model()

from .common import get_request_workspace_or_403


class ConversationListView(APIView):
    def get(self, request):
        updated_after = request.query_params.get('updated_after', '').strip()
        workspace, error_response = get_request_workspace_or_403(request)
        if error_response is not None:
            return error_response
        unread_messages = (
            Message.objects.filter(conversation_id=OuterRef('pk'))
            .exclude(sender_id=request.user.id)
            .exclude(
                receipts__user_id=request.user.id,
                receipts__read_at__isnull=False,
            )
            .order_by()
            .values('conversation_id')
            .annotate(total=Count('id'))
            .values('total')
        )
        latest_messages = Message.objects.select_related('sender').order_by(
            '-created_at',
            '-id',
        )[:1]
        conversations = (
            Conversation.objects.filter(
                participants=request.user,
                workspace=workspace,
            )
            .annotate(
                unread_count_value=Coalesce(
                    Subquery(unread_messages, output_field=IntegerField()),
                    Value(0),
                )
            )
            .prefetch_related(
                Prefetch(
                    'participants',
                    queryset=User.objects.only('id').order_by('id'),
                    to_attr='ordered_participants',
                ),
                Prefetch(
                    'messages',
                    queryset=latest_messages,
                    to_attr='latest_messages',
                ),
            )
            .distinct()
        )
        if updated_after:
            parsed_updated_after = parse_datetime(updated_after)
            if parsed_updated_after is None:
                return Response(
                    {'detail': 'updated_after must be an ISO-8601 datetime.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if timezone.is_naive(parsed_updated_after):
                parsed_updated_after = timezone.make_aware(parsed_updated_after)
            conversations = conversations.filter(updated_at__gt=parsed_updated_after)
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
        other_user_is_active_member = WorkspaceMember.objects.filter(
            workspace=workspace,
            organization_member__user=other_user,
            organization_member__is_active=True,
            is_active=True,
        ).exists()
        if not other_user_is_active_member:
            return Response(
                {'detail': 'User is not an active member of this workspace.'},
                status=status.HTTP_404_NOT_FOUND,
            )

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
