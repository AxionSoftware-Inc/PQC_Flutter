import '../../../core/database/app_database.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../crypto/chat_cipher_service.dart';
import '../../crypto/chat_crypto_context.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../security/key_verification_service.dart';
import '../data/chat_remote_data_source.dart';
import '../data/chat_realtime_service.dart';
import '../data/outbox_store.dart';
import '../data/private_conversation_security_coordinator.dart';
import 'chat_local_store.dart';
import 'chat_models.dart';

class ChatCryptoRequest {
  const ChatCryptoRequest({
    required this.currentUserId,
    required this.conversation,
    required this.usersById,
  });

  final int currentUserId;
  final Conversation conversation;
  final Map<int, AppUser> usersById;
}

class ChatCryptoService {
  static const peerPqcKeyNotReadyMessage =
      'Peer PQC device key is not ready yet. Ask them to reopen the app.';

  const ChatCryptoService({required this.cipherService});

  final ChatCipherService cipherService;

  Future<String> encrypt({
    required ChatCryptoRequest request,
    required String plaintext,
  }) {
    return cipherService.encrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
      ),
      plaintext: plaintext,
    );
  }

  Future<String> decrypt({
    required ChatCryptoRequest request,
    required String payload,
  }) {
    return cipherService.decrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
      ),
      payload: payload,
    );
  }
}

class ChatTrustService {
  const ChatTrustService({
    required this.keyVerificationService,
    required this.privateConversationSecurityCoordinator,
  });

  final KeyVerificationService keyVerificationService;
  final PrivateConversationSecurityCoordinator
  privateConversationSecurityCoordinator;

  Future<Map<int, UserKeyTrust>> buildUserTrustMap(
    Iterable<AppUser> users,
  ) {
    return keyVerificationService.buildUserTrustMap(users);
  }

  Future<ConversationTrustState> loadConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    return ConversationTrustState(trust: trust);
  }

  Future<void> verifyConversationPeerKey({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    final peerUser = trust.peerUser;
    if (peerUser == null) {
      return;
    }
    await keyVerificationService.verifyUser(peerUser);
  }

  Future<void> prepareForSend({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    return privateConversationSecurityCoordinator.prepareForSend(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
      onUserUpdated: (_) {},
    );
  }
}

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
  }) async {
    var conversations = await remoteDataSource.fetchConversations(
      updatedAfter: updatedAfter,
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
    if (conversation.isGroup || plaintext != '[decrypt-error]') {
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
  const MessageSyncResult({
    required this.messages,
    this.lastMessageId,
  });

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
    final existingRows = await localStore.readMessageRows(conversation.id);
    final syncState = await localStore.readSyncState(conversation.id);
    final deltaAfterId = existingRows.isEmpty
        ? null
        : syncState?.lastMessageId ?? previousLastMessageId;
    var messages = await remoteDataSource.fetchMessages(
      conversation.id,
      afterId: deltaAfterId,
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
    await _retryStoredDecryptErrors(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: usersById,
      refreshUsers: refreshUsers,
    );
    final mergedRemote = await localStore.readMessages(conversation.id);
    return MessageSyncResult(
      messages: mergedRemote,
      lastMessageId: messages.isNotEmpty ? messages.last.id : null,
    );
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
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
    if (conversation.isGroup || plaintext != '[decrypt-error]') {
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
      refreshUsers: refreshUsers,
    );
    if (plaintext != '[decrypt-error]') {
      return plaintext;
    }
    if (message.senderId != currentUserId) {
      return plaintext;
    }
    final existingByMessageId = existingById[message.id];
    if (existingByMessageId != null &&
        existingByMessageId.plaintextBody.isNotEmpty &&
        existingByMessageId.plaintextBody != '[decrypt-error]') {
      return existingByMessageId.plaintextBody;
    }
    final clientMessageId = message.clientMessageId;
    if (clientMessageId.isNotEmpty) {
      final existingByQueuedClientId = existingByClientId[clientMessageId];
      if (existingByQueuedClientId != null &&
          existingByQueuedClientId.plaintextBody.isNotEmpty &&
          existingByQueuedClientId.plaintextBody != '[decrypt-error]') {
        return existingByQueuedClientId.plaintextBody;
      }
    }
    return plaintext;
  }

  Future<void> _retryStoredDecryptErrors({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
  }) async {
    final rows = await localStore.readMessageRows(conversation.id);
    for (final row in rows) {
      final unprotectedRow = await localStore.unprotectMessageRow(row);
      if (unprotectedRow.plaintextBody != '[decrypt-error]' ||
          unprotectedRow.encryptedBody.isEmpty) {
        continue;
      }
      final plaintext = await _decryptPayloadWithUserRefresh(
        conversation: conversation,
        currentUserId: currentUserId,
        usersById: usersById,
        payload: unprotectedRow.encryptedBody,
        refreshUsers: refreshUsers,
      );
      if (plaintext == '[decrypt-error]') {
        continue;
      }
      await localStore.repairPlaintext(row: unprotectedRow, plaintext: plaintext);
    }
  }
}

class OutgoingMessageService {
  const OutgoingMessageService({
    required this.remoteDataSource,
    required this.cryptoService,
    required this.localStore,
    required this.outboxStore,
  });

  final ChatRemoteDataSource remoteDataSource;
  final ChatCryptoService cryptoService;
  final ChatLocalStore localStore;
  final OutboxStore outboxStore;

  Future<ChatMessage> sendMessage({
    required SendMessageCommand command,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation) persistConversation,
  }) async {
    final now = DateTime.now().toUtc();
    final uploadedAttachments = <ChatAttachment>[];
    for (final attachment in command.attachments) {
      uploadedAttachments.add(
        await remoteDataSource.uploadAttachment(
          command.conversation.id,
          filename: attachment.filename,
          bytes: attachment.bytes,
          mimeType: attachment.mimeType,
        ),
      );
    }
    final clientMessageId =
        '${command.conversation.id}_${command.currentUserId}_${now.microsecondsSinceEpoch}';
    final currentUser = usersById[command.currentUserId];
    final queued = QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: command.conversation.id,
      senderId: command.currentUserId,
      senderName: currentUser?.displayName ?? 'You',
      plaintext: command.text,
      createdAt: now,
      deliveryState: MessageDeliveryState.pending,
    );
    await outboxStore.upsert(queued);

    try {
      final sent = await _sendQueuedMessage(
        queued,
        conversation: command.conversation,
        currentUserId: command.currentUserId,
        usersById: usersById,
        refreshUsers: refreshUsers,
        persistConversation: persistConversation,
        messageType: uploadedAttachments.isEmpty ? 'text' : command.messageType,
        attachmentIds: uploadedAttachments.map((item) => item.id).toList(),
      );
      await outboxStore.remove(clientMessageId);
      return sent;
    } on ApiException catch (error) {
      if (uploadedAttachments.isNotEmpty) {
        await outboxStore.remove(clientMessageId);
        throw ApiException(
          'Attachment send failed. Please attach files again and retry.',
          statusCode: error.statusCode,
          code: error.code,
          isRetryable: false,
        );
      }
      final state = error.isRetryable
          ? MessageDeliveryState.failedRetryable
          : MessageDeliveryState.failedPermanent;
      await outboxStore.upsert(
        queued.copyWith(
          retryCount: queued.retryCount + (error.isRetryable ? 1 : 0),
          nextRetryAt: error.isRetryable
              ? DateTime.now().toUtc().add(
                  Duration(seconds: (queued.retryCount + 1) * 2),
                )
              : null,
          deliveryState: state,
          failureReason: error.message,
        ),
      );
      return queued
          .copyWith(deliveryState: state, failureReason: error.message)
          .toChatMessage();
    }
  }

  Future<void> flushPendingMessages({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation) persistConversation,
  }) async {
    final pending = await outboxStore.readForConversation(conversation.id);
    for (final item in pending) {
      if (item.deliveryState == MessageDeliveryState.failedPermanent) {
        continue;
      }
      if (item.nextRetryAt != null &&
          item.nextRetryAt!.isAfter(DateTime.now().toUtc())) {
        continue;
      }
      try {
        await _sendQueuedMessage(
          item.copyWith(deliveryState: MessageDeliveryState.pending),
          conversation: conversation,
          currentUserId: currentUserId,
          usersById: usersById,
          refreshUsers: refreshUsers,
          persistConversation: persistConversation,
        );
        await outboxStore.remove(item.clientMessageId);
      } on ApiException catch (error) {
        await outboxStore.upsert(
          item.copyWith(
            retryCount: item.retryCount + (error.isRetryable ? 1 : 0),
            nextRetryAt: error.isRetryable
                ? DateTime.now().toUtc().add(
                    Duration(seconds: (item.retryCount + 1) * 2),
                  )
                : null,
            deliveryState: error.isRetryable
                ? MessageDeliveryState.failedRetryable
                : MessageDeliveryState.failedPermanent,
            failureReason: error.message,
          ),
        );
      }
    }
  }

  Future<void> retryMessage({
    required Conversation conversation,
    required int currentUserId,
    required String clientMessageId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation) persistConversation,
  }) async {
    final queued = await outboxStore.readForConversation(conversation.id);
    final target = queued.where((item) => item.clientMessageId == clientMessageId);
    if (target.isEmpty) {
      return;
    }
    await outboxStore.upsert(
      target.first.copyWith(
        retryCount: 0,
        nextRetryAt: null,
        deliveryState: MessageDeliveryState.pending,
        failureReason: null,
      ),
    );
    await flushPendingMessages(
      conversation: conversation,
      currentUserId: currentUserId,
      usersById: usersById,
      refreshUsers: refreshUsers,
      persistConversation: persistConversation,
    );
  }

  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation) persistConversation,
    String messageType = 'text',
    List<int> attachmentIds = const [],
  }) async {
    final payload = queued.encryptedPayload.isNotEmpty
        ? queued.encryptedPayload
        : await _encryptPayloadWithUserRefresh(
            conversation: conversation,
            currentUserId: currentUserId,
            usersById: usersById,
            plaintext: queued.plaintext,
            refreshUsers: refreshUsers,
          );
    if (queued.encryptedPayload.isEmpty) {
      await outboxStore.upsert(queued.copyWith(encryptedPayload: payload));
    }
    final message = await remoteDataSource.sendMessage(
      conversation.id,
      payload,
      clientMessageId: queued.clientMessageId,
      messageType: messageType,
      attachmentIds: attachmentIds,
    );
    final decoded = ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      senderName: message.senderName,
      body: message.senderId == currentUserId
          ? queued.plaintext
          : await _decryptPayloadWithUserRefresh(
              conversation: conversation,
              currentUserId: currentUserId,
              usersById: usersById,
              payload: message.body,
              refreshUsers: refreshUsers,
            ),
      createdAt: message.createdAt,
      messageType: message.messageType,
      attachmentCount: message.attachmentCount,
      attachments: message.attachments,
      clientMessageId: message.clientMessageId,
      deliveryState: MessageDeliveryState.sent,
    );
    await localStore.persistMessage(decoded: decoded, encryptedBody: message.body);
    await persistConversation(
      conversation.copyWith(
        lastMessagePreview: decoded.body.length > 80
            ? decoded.body.substring(0, 80)
            : decoded.body,
        updatedAt: decoded.createdAt,
      ),
    );
    return decoded;
  }

  Future<String> _encryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String plaintext,
    required Future<void> Function() refreshUsers,
  }) async {
    try {
      return await cryptoService.encrypt(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
        ),
        plaintext: plaintext,
      );
    } catch (error) {
      if (error is! ChatEncryptionException ||
          conversation.isGroup ||
          error.message != ChatCryptoService.peerPqcKeyNotReadyMessage) {
        rethrow;
      }
      await refreshUsers();
      return cryptoService.encrypt(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
        ),
        plaintext: plaintext,
      );
    }
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
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
    if (conversation.isGroup || plaintext != '[decrypt-error]') {
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

class ChatRealtimeCoordinator {
  const ChatRealtimeCoordinator({
    required this.localStore,
    required this.cryptoService,
  });

  final ChatLocalStore localStore;
  final ChatCryptoService cryptoService;

  Future<Conversation?> handleEvent({
    required ChatRealtimeEvent event,
    required Conversation knownConversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation) persistConversation,
  }) async {
    if (event.event == 'conversation.updated') {
      return null;
    }
    if (event.event != 'message.created') {
      return null;
    }
    final conversationId = event.payload['conversation_id'] as int?;
    if (conversationId == null) {
      return null;
    }
    final payload = event.payload['body'] as String? ?? '';
    final plaintext = await _decryptPayloadWithUserRefresh(
      conversation: knownConversation,
      currentUserId: currentUserId,
      usersById: usersById,
      payload: payload,
      refreshUsers: refreshUsers,
    );
    final message = ChatMessage(
      id: event.payload['id'] as int,
      conversationId: conversationId,
      senderId: event.payload['sender_id'] as int,
      senderName: event.payload['sender_name'] as String? ?? '',
      body: plaintext,
      createdAt: DateTime.parse(event.payload['created_at'] as String),
      messageType: event.payload['message_type'] as String? ?? 'text',
      attachmentCount: event.payload['attachment_count'] as int? ?? 0,
      attachments: (event.payload['attachments'] as List<dynamic>? ?? const [])
          .map((item) => ChatAttachment.fromJson(item as Map<String, dynamic>))
          .toList(),
      clientMessageId: event.payload['client_message_id'] as String? ?? '',
    );
    await localStore.persistMessage(decoded: message, encryptedBody: payload);
    final updatedConversation = knownConversation.copyWith(
      lastMessagePreview: plaintext.length > 80
          ? plaintext.substring(0, 80)
          : plaintext,
      updatedAt: DateTime.parse(event.payload['created_at'] as String),
    );
    await persistConversation(updatedConversation);
    return updatedConversation;
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
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
    if (conversation.isGroup || plaintext != '[decrypt-error]') {
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
