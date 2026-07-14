from django.urls import path

from chat.views import (
    AttachmentDownloadChunkView,
    AttachmentDownloadDescriptorView,
    AttachmentDownloadFileView,
    AttachmentSessionChunkView,
    AttachmentSessionCompleteView,
    AttachmentSessionCreateView,
    AttachmentSessionDetailView,
    AttachmentUploadView,
    ConversationListView,
    CryptoProtocolCapabilitiesView,
    ConversationKeyEnvelopeView,
    MessageListCreateView,
    MessageActionView,
    MessageReactionView,
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
    path('messages/<int:message_id>', MessageActionView.as_view(), name='message-action'),
    path('messages/<int:message_id>/reaction', MessageReactionView.as_view(), name='message-reaction'),
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
        'attachments/<int:attachment_id>/file',
        AttachmentDownloadFileView.as_view(),
        name='attachment-download-file',
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
