part of 'chat_facade.dart';

mixin _ChatFacadeMessaging on _ChatFacadeBase {
  Future<void> warmSendPipeline({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _refreshPrivateUsersIfNeeded(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    await _outgoingMessageService.warmProtocolCapabilities();
  }

  Future<ChatMessage> sendMessage(SendMessageCommand command) async {
    _activeCurrentUserId = command.currentUserId;
    await _ensureUsersLoaded();
    await _refreshUsersForSecureSend();
    await _refreshPrivateUsersIfNeeded(
      conversation: command.conversation,
      currentUserId: command.currentUserId,
    );
    await _trustService.prepareForSend(
      currentUserId: command.currentUserId,
      conversation: command.conversation,
      usersById: _usersById,
    );
    return _outgoingMessageService.sendMessage(
      command: command,
      usersById: _usersById,
      refreshUsers: fetchUsers,
      persistConversation: _persistConversation,
    );
  }

  Future<ChatMessage> editMessage(int messageId, String body) {
    return _remoteDataSource.editMessage(messageId, body);
  }

  Future<void> deleteMessage(int messageId) {
    return _remoteDataSource.deleteMessage(messageId);
  }

  Future<void> markMessageRead(int messageId) {
    return _remoteDataSource.markMessageRead(messageId);
  }

  Future<Map<String, dynamic>> setReaction(int messageId, String emoji) {
    return _remoteDataSource.setReaction(messageId, emoji);
  }

  Future<void> removeReaction(int messageId) {
    return _remoteDataSource.removeReaction(messageId);
  }

  Future<void> retryMessage({
    required Conversation conversation,
    required int currentUserId,
    required String clientMessageId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _outgoingMessageService.retryMessage(
      conversation: conversation,
      currentUserId: currentUserId,
      clientMessageId: clientMessageId,
      usersById: _usersById,
      refreshUsers: fetchUsers,
      persistConversation: _persistConversation,
    );
  }

  Future<ConversationTrustState> loadConversationTrust({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    return _trustService.loadConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
  }

  Future<void> verifyConversationPeerKey({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _trustService.verifyConversationPeerKey(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
  }

  Future<Map<int, UserKeyTrust>> buildUserTrustMap() async {
    await _ensureUsersLoaded();
    return _trustService.buildUserTrustMap(_usersById.values);
  }
}
