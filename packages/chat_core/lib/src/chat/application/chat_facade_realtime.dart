part of 'chat_facade.dart';

mixin _ChatFacadeRealtime on _ChatFacadeBase {
  Future<void> resumePendingWork({required int currentUserId}) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    if (_attachmentTransferFacade != null) {
      await _attachmentTransferFacade.resumePendingDownloads();
    }
    // KPI conversations are intentionally hidden from the normal chat list,
    // but their durable outbox entries must be retried after a restart too.
    final rows = await _localStore.readAllConversationRows();
    for (final row in rows) {
      final conversation = await _localStore.mapConversationRow(
        row: row,
        knownConversation: _conversationsById[row.id],
      );
      _conversationsById[conversation.id] = conversation;
      // Attachment messages are user-driven and can be large. Never restart
      // their upload automatically during app startup; otherwise opening a
      // chat can spend minutes replaying old file sends.
      try {
        await _outgoingMessageService.flushPendingMessages(
          conversation: conversation,
          currentUserId: currentUserId,
          usersById: _usersById,
          refreshUsers: _refreshUsersForSecureSend,
          persistConversation: _persistConversation,
        );
      } on ApiException {
        // Keep the queue persisted; flush will retry later.
      }
    }
  }

  @override
  Future<void> _handleRealtimeEvent(ChatRealtimeEvent event) async {
    final conversationId = event.payload['conversation_id'] as int?;
    if (conversationId == null) {
      return;
    }
    final knownConversation = _conversationsById[conversationId];
    final currentUserId = _activeCurrentUserId;
    if (knownConversation == null || currentUserId == null) {
      return;
    }
    final updatedConversation = await _realtimeCoordinator.handleEvent(
      event: event,
      knownConversation: knownConversation,
      currentUserId: currentUserId,
      usersById: _usersById,
      refreshUsers: fetchUsers,
      persistConversation: _persistConversation,
    );
    if (updatedConversation != null) {
      _conversationsById[updatedConversation.id] = updatedConversation;
    }
  }
}
