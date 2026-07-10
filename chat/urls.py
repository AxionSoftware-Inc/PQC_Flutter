from django.urls import path

from chat.views import (
    AttachmentUploadView,
    ConversationListView,
    ConversationKeyEnvelopeView,
    MessageListCreateView,
    PrivateConversationView,
)


urlpatterns = [
    path('conversations', ConversationListView.as_view(), name='conversations'),
    path(
        'conversations/<int:conversation_id>/messages',
        MessageListCreateView.as_view(),
        name='conversation-messages',
    ),
    path(
        'conversations/<int:conversation_id>/attachments',
        AttachmentUploadView.as_view(),
        name='conversation-attachments',
    ),
    path(
        'conversations/<int:conversation_id>/keys',
        ConversationKeyEnvelopeView.as_view(),
        name='conversation-keys',
    ),
    path(
        'private-conversations',
        PrivateConversationView.as_view(),
        name='private-conversations',
    ),
]
