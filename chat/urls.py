from django.urls import path

from chat.views import (
    AttachmentDownloadChunkView,
    AttachmentDownloadDescriptorView,
    AttachmentSessionChunkView,
    AttachmentSessionCompleteView,
    AttachmentSessionCreateView,
    AttachmentSessionDetailView,
    AttachmentUploadView,
    ConversationListView,
    CryptoProtocolCapabilitiesView,
    ConversationKeyEnvelopeView,
    MessageListCreateView,
    PrivateConversationView,
)


urlpatterns = [
    path('crypto/protocols', CryptoProtocolCapabilitiesView.as_view(), name='crypto-protocols'),
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
        'conversations/<int:conversation_id>/attachment-sessions',
        AttachmentSessionCreateView.as_view(),
        name='conversation-attachment-sessions',
    ),
    path(
        'attachment-sessions/<str:session_id>',
        AttachmentSessionDetailView.as_view(),
        name='attachment-session-detail',
    ),
    path(
        'attachment-sessions/<str:session_id>/chunks/<int:chunk_index>',
        AttachmentSessionChunkView.as_view(),
        name='attachment-session-chunk',
    ),
    path(
        'attachment-sessions/<str:session_id>/complete',
        AttachmentSessionCompleteView.as_view(),
        name='attachment-session-complete',
    ),
    path(
        'attachments/<int:attachment_id>/download',
        AttachmentDownloadDescriptorView.as_view(),
        name='attachment-download',
    ),
    path(
        'attachments/<int:attachment_id>/chunks/<int:chunk_index>',
        AttachmentDownloadChunkView.as_view(),
        name='attachment-download-chunk',
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
