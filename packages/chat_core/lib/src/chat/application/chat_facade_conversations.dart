part of 'chat_facade.dart';

// ignore_for_file: annotate_overrides

mixin _ChatFacadeConversations on _ChatFacadeBase {
  /// Registers a conversation before the first send so a crash between local
  /// queueing and network delivery can still recover it on the next startup.
  Future<void> ensureConversationCached(Conversation conversation) async {
    _conversationsById[conversation.id] = conversation;
    await _persistConversation(conversation);
  }

  Future<ChatListState> loadChatList({
    required int currentUserId,
    String searchQuery = '',
  }) async {
    _activeCurrentUserId = currentUserId;
    final users = await fetchUsers();
    final existingRows = await _localStore.readVisibleConversationRows(
      _activeWorkspaceId,
    );
    final syncResult = await _conversationSyncService.fetchConversations(
      currentUserId: currentUserId,
      usersById: _usersById,
      updatedAfter: _lastConversationSyncAt,
      search: searchQuery,
      hasLocalRows: existingRows.isNotEmpty,
      refreshUsers: fetchUsers,
    );
    _lastConversationSyncAt = syncResult.syncedAt;
    for (final conversation in syncResult.conversations) {
      await _persistConversation(conversation);
    }
    final rows = await _localStore.readVisibleConversationRows(
      _activeWorkspaceId,
    );
    final conversations = <Conversation>[];
    for (final row in rows) {
      conversations.add(
        await _localStore.mapConversationRow(
          row: row,
          knownConversation: _conversationsById[row.id],
        ),
      );
    }
    final trustByUserId = await _trustService.buildUserTrustMap(
      _usersById.values,
    );
    return ChatListState(
      users: users,
      conversations: conversations,
      trustByUserId: trustByUserId,
    );
  }

  Future<Conversation> openPrivateConversation(int otherUserId) async {
    final conversation = await _remoteDataSource.openPrivateConversation(
      otherUserId,
    );
    await _persistConversation(conversation);
    return conversation;
  }

  Future<ChatConversationState> loadConversationMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _refreshPrivateUsersIfNeeded(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    final syncResult = await _messageSyncService.syncMessages(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: _usersById,
      previousLastMessageId: _lastMessageIdByConversation[conversation.id],
      refreshUsers: fetchUsers,
    );
    if (syncResult.lastMessageId != null) {
      _lastMessageIdByConversation[conversation.id] = syncResult.lastMessageId!;
    }
    final pending = await _outboxStore.readForConversation(conversation.id);
    final mergedMessages = _mergeMessages(syncResult.messages, pending);
    final trust = conversation.isGroup
        ? null
        : await _trustService.loadConversationTrust(
            currentUserId: currentUserId,
            conversation: conversation,
            usersById: _usersById,
          );
    return ChatConversationState(messages: mergedMessages, trust: trust);
  }

  /// Returns the encrypted-at-rest local window without waiting for users,
  /// trust, or network synchronization. The controller uses this for instant
  /// first paint and replaces it with the authoritative sync result later.
  Future<List<ChatMessage>> readCachedConversationMessages(int conversationId) {
    return _localStore.readMessages(conversationId, limit: 50);
  }

  Future<ChatConversationState> loadOlderConversationMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    final syncResult = await _messageSyncService.syncOlderMessages(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: _usersById,
      refreshUsers: fetchUsers,
    );
    final pending = await _outboxStore.readForConversation(conversation.id);
    return ChatConversationState(
      messages: _mergeMessages(syncResult.messages, pending),
    );
  }

  Future<void> _ensureUsersLoaded() async {
    if (_usersById.isNotEmpty) {
      return;
    }
    await fetchUsers();
  }

  Future<void> _refreshUsersForSecureSend() async {
    final last = _lastSecureSendUsersRefreshAt;
    if (_usersById.isNotEmpty &&
        last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return;
    }
    final inFlight = _secureUsersRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _refreshSecureUsersOnce();
    _secureUsersRefreshInFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_secureUsersRefreshInFlight, operation)) {
        _secureUsersRefreshInFlight = null;
      }
    }
  }

  Future<void> _refreshSecureUsersOnce() async {
    try {
      await fetchUsers();
    } on ApiException catch (error) {
      if (!error.isRetryable) {
        rethrow;
      }
    }
  }

  Future<void> _refreshPrivateUsersIfNeeded({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    if (conversation.isGroup) {
      return;
    }
    final lastRefresh = _privateUsersRefreshAt[conversation.id];
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(seconds: 15)) {
      return;
    }
    final resolution = _devicePolicy.resolvePrivatePeerPqcDevice(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
    if (resolution.isReady) {
      _privateUsersRefreshAt[conversation.id] = DateTime.now();
      return;
    }
    await fetchUsers();
    _privateUsersRefreshAt[conversation.id] = DateTime.now();
  }

  Future<void> _persistConversation(Conversation conversation) async {
    await _localStore.persistConversation(
      conversation: conversation,
      activeWorkspaceId: _activeWorkspaceId,
    );
    _conversationsById[conversation.id] = conversation.copyWith(
      workspaceId: conversation.workspaceId > 0
          ? conversation.workspaceId
          : _activeWorkspaceId,
    );
  }

  List<ChatMessage> _mergeMessages(
    List<ChatMessage> remote,
    List<QueuedOutgoingMessage> pending,
  ) {
    final byClientId = <String, ChatMessage>{};
    final merged = <ChatMessage>[];
    for (final message in remote) {
      if (message.clientMessageId.isNotEmpty) {
        byClientId[message.clientMessageId] = message;
      }
      merged.add(message);
    }
    for (final item in pending) {
      if (byClientId.containsKey(item.clientMessageId)) {
        continue;
      }
      merged.add(item.toChatMessage());
    }
    merged.sort((a, b) {
      final createdCompare = a.createdAt.compareTo(b.createdAt);
      if (createdCompare != 0) {
        return createdCompare;
      }
      return a.id.compareTo(b.id);
    });
    return merged;
  }
}
