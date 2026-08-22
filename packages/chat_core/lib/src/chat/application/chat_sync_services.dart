part of 'chat_services.dart';

class ConversationSyncResult {
  const ConversationSyncResult({
    required this.conversations,
    required this.syncedAt,
  });

  final List<Conversation> conversations;
  final DateTime syncedAt;
}

class ConversationSyncService {
  const ConversationSyncService({
    required this.remoteDataSource,
    required this.cryptoService,
  });

  final ChatRemoteDataSource remoteDataSource;
  final ChatCryptoService cryptoService;

  Future<ConversationSyncResult> fetchConversations({
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required DateTime? updatedAfter,
    required bool hasLocalRows,
    required Future<void> Function() refreshUsers,
    String search = '',
  }) async {
    var conversations = await remoteDataSource.fetchConversations(
      updatedAfter: updatedAfter,
      search: search,
    );
    if (conversations.isEmpty && !hasLocalRows && updatedAfter != null) {
      conversations = await remoteDataSource.fetchConversations();
    }

    final merged = <Conversation>[];
    for (final conversation in conversations) {
      final preview = conversation.lastMessagePreview.isEmpty
          ? ''
          : await _decryptPayloadWithUserRefresh(
              currentUserId: currentUserId,
              conversation: conversation,
              usersById: usersById,
              payload: conversation.lastMessagePreview,
              refreshUsers: refreshUsers,
            );
      merged.add(
        conversation.copyWith(
          lastMessagePreview: preview.length > 80
              ? preview.substring(0, 80)
              : preview,
        ),
      );
    }
    return ConversationSyncResult(
      conversations: merged,
      syncedAt: DateTime.now().toUtc(),
    );
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required String payload,
    required Future<void> Function() refreshUsers,
  }) async {
    final plaintext = await cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
      ),
      payload: payload,
    );
    if (!cryptoService.isDecryptFailureMarker(plaintext)) {
      return plaintext;
    }
    await refreshUsers();
    return cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
      ),
      payload: payload,
    );
  }
}

class MessageSyncResult {
  const MessageSyncResult({required this.messages, this.lastMessageId});

  final List<ChatMessage> messages;
  final int? lastMessageId;
}

class MessageSyncService {
  const MessageSyncService({
    required this.remoteDataSource,
    required this.localStore,
    required this.cryptoService,
  });

  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalStore localStore;
  final ChatCryptoService cryptoService;

  Future<MessageSyncResult> syncMessages({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required int? previousLastMessageId,
    required Future<void> Function() refreshUsers,
  }) async {
    // Only the visible recent window is needed during polling. Older rows are
    // loaded explicitly by syncOlderMessages and must not block every refresh.
    final existingRows = await localStore.readMessageRows(
      conversation.id,
      limit: 50,
    );
    final syncState = await localStore.readSyncState(conversation.id);
    final deltaAfterId = existingRows.isEmpty
        ? null
        : syncState?.lastMessageId ?? previousLastMessageId;
    var messages = await remoteDataSource.fetchMessages(
      conversation.id,
      afterId: deltaAfterId,
      limit: 50,
    );
    if (messages.isEmpty && existingRows.isEmpty && deltaAfterId != null) {
      messages = await remoteDataSource.fetchMessages(conversation.id);
    }

    final unprotectedExistingRows = <MessagesTableData>[];
    for (final row in existingRows) {
      unprotectedExistingRows.add(await localStore.unprotectMessageRow(row));
    }
    final existingById = {
      for (final row in unprotectedExistingRows) row.id: row,
    };
    final existingByClientId = {
      for (final row in unprotectedExistingRows)
        if (row.clientMessageId.isNotEmpty) row.clientMessageId: row,
    };

    for (final message in messages) {
      final plaintext = await _resolveMessagePlaintext(
        conversation: conversation,
        currentUserId: currentUserId,
        usersById: usersById,
        message: message,
        existingById: existingById,
        existingByClientId: existingByClientId,
        refreshUsers: refreshUsers,
      );
      await localStore.persistMessage(
        decoded: message.copyWith(body: plaintext),
        encryptedBody: message.body,
      );
    }
    if (messages.isNotEmpty) {
      await localStore.upsertSyncState(
        conversationId: conversation.id,
        lastMessageId: messages.last.id,
      );
    }
    // A key restored after reinstall should repair visible decrypt failures
    // automatically, without rescanning the entire conversation history.
    for (final row in unprotectedExistingRows) {
      if (!cryptoService.isDecryptFailureMarker(row.plaintextBody) ||
          row.encryptedBody.isEmpty) {
        continue;
      }
      final repaired = await _decryptPayloadWithUserRefresh(
        conversation: conversation,
        currentUserId: currentUserId,
        usersById: usersById,
        payload: row.encryptedBody,
        messageId: row.clientMessageId.isNotEmpty
            ? row.clientMessageId
            : row.id.toString(),
        senderId: row.senderId,
        refreshUsers: refreshUsers,
      );
      if (!cryptoService.isDecryptFailureMarker(repaired)) {
        await localStore.repairPlaintext(row: row, plaintext: repaired);
      }
    }
    // Avoid scanning every historical row on each polling refresh. Recovery
    // retries happen when a keyset is restored or an older page is requested.
    final mergedRemote = await localStore.readMessages(
      conversation.id,
      limit: 50,
    );
    return MessageSyncResult(
      messages: mergedRemote,
      lastMessageId: messages.isNotEmpty ? messages.last.id : null,
    );
  }

  /// Loads an older page without touching the sync cursor used for new data.
  /// Key material remains in the durability registry; only the requested
  /// ciphertexts are fetched and decrypted.
  Future<MessageSyncResult> syncOlderMessages({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
  }) async {
    final existingRows = await localStore.readMessageRows(
      conversation.id,
      limit: null,
    );
    final oldestId = existingRows
        .map((row) => row.id)
        .where((id) => id > 0)
        .fold<int?>(
          null,
          (oldest, id) => oldest == null || id < oldest ? id : oldest,
        );
    if (oldestId == null) {
      return const MessageSyncResult(messages: []);
    }
    final messages = await remoteDataSource.fetchMessages(
      conversation.id,
      beforeId: oldestId,
      limit: 50,
    );
    if (messages.isEmpty) {
      return MessageSyncResult(
        messages: await localStore.readMessages(conversation.id, limit: null),
      );
    }
    final rows = <MessagesTableData>[];
    for (final row in existingRows) {
      rows.add(await localStore.unprotectMessageRow(row));
    }
    final existingById = {for (final row in rows) row.id: row};
    final existingByClientId = {
      for (final row in rows)
        if (row.clientMessageId.isNotEmpty) row.clientMessageId: row,
    };
    for (final message in messages) {
      final plaintext = await _resolveMessagePlaintext(
        conversation: conversation,
        currentUserId: currentUserId,
        usersById: usersById,
        message: message,
        existingById: existingById,
        existingByClientId: existingByClientId,
        refreshUsers: refreshUsers,
      );
      await localStore.persistMessage(
        decoded: message.copyWith(body: plaintext),
        encryptedBody: message.body,
      );
    }
    return MessageSyncResult(
      messages: await localStore.readMessages(conversation.id, limit: null),
      lastMessageId: messages.last.id,
    );
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String payload,
    required String messageId,
    required int senderId,
    required Future<void> Function() refreshUsers,
  }) async {
    final plaintext = await cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
        messageId: messageId,
        senderId: senderId,
      ),
      payload: payload,
    );
    if (!cryptoService.isDecryptFailureMarker(plaintext)) {
      return plaintext;
    }
    await refreshUsers();
    return cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
        messageId: messageId,
        senderId: senderId,
      ),
      payload: payload,
    );
  }

  Future<String> _resolveMessagePlaintext({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required ChatMessage message,
    required Map<int, MessagesTableData> existingById,
    required Map<String, MessagesTableData> existingByClientId,
    required Future<void> Function() refreshUsers,
  }) async {
    final plaintext = await _decryptPayloadWithUserRefresh(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: usersById,
      payload: message.body,
      messageId: message.clientMessageId.isNotEmpty
          ? message.clientMessageId
          : message.id.toString(),
      senderId: message.senderId,
      refreshUsers: refreshUsers,
    );
    if (!cryptoService.isDecryptFailureMarker(plaintext)) {
      return plaintext;
    }
    if (message.senderId != currentUserId) {
      return plaintext;
    }
    final existingByMessageId = existingById[message.id];
    if (existingByMessageId != null &&
        existingByMessageId.plaintextBody.isNotEmpty &&
        !cryptoService.isDecryptFailureMarker(
          existingByMessageId.plaintextBody,
        )) {
      return existingByMessageId.plaintextBody;
    }
    final clientMessageId = message.clientMessageId;
    if (clientMessageId.isNotEmpty) {
      final existingByQueuedClientId = existingByClientId[clientMessageId];
      if (existingByQueuedClientId != null &&
          existingByQueuedClientId.plaintextBody.isNotEmpty &&
          !cryptoService.isDecryptFailureMarker(
            existingByQueuedClientId.plaintextBody,
          )) {
        return existingByQueuedClientId.plaintextBody;
      }
    }
    return plaintext;
  }
}
