import 'dart:convert';

import '../../../core/models/app_user.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../../core/database/app_database.dart';
import '../../../core/storage/local_data_protector.dart';
import 'package:drift/drift.dart' as drift;
import '../../crypto/chat_cipher_service.dart';
import '../../crypto/chat_crypto_context.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../security/key_verification_service.dart';
import 'chat_realtime_service.dart';
import 'chat_remote_data_source.dart';
import 'outbox_store.dart';
import 'private_conversation_security_coordinator.dart';

class ChatRepository {
  static const _peerPqcKeyNotReadyMessage =
      'Peer PQC device key is not ready yet. Ask them to reopen the app.';

  ChatRepository({
    required ChatRemoteDataSource remoteDataSource,
    required ChatCipherService cipherService,
    required KeyVerificationService keyVerificationService,
    required PrivateConversationSecurityCoordinator
    privateConversationSecurityCoordinator,
    AppDatabase? database,
    LocalDataProtector? localDataProtector,
    ChatRealtimeService? realtimeService,
    OutboxStore? outboxStore,
  }) : this._internal(
         remoteDataSource: remoteDataSource,
         cipherService: cipherService,
         keyVerificationService: keyVerificationService,
         privateConversationSecurityCoordinator:
             privateConversationSecurityCoordinator,
         database: database ?? AppDatabase(),
         localDataProtector: localDataProtector ?? LocalDataProtector(),
         realtimeService: realtimeService,
         outboxStore: outboxStore,
       );

  ChatRepository._internal({
    required this.remoteDataSource,
    required this.cipherService,
    required this.keyVerificationService,
    required this.privateConversationSecurityCoordinator,
    required AppDatabase database,
    required LocalDataProtector localDataProtector,
    required this.realtimeService,
    OutboxStore? outboxStore,
  }) : _database = database,
       _localDataProtector = localDataProtector,
       outboxStore =
           outboxStore ??
           OutboxStore(
             database: database,
             localDataProtector: localDataProtector,
           ) {
    realtimeService?.events.listen(_handleRealtimeEvent);
  }

  final ChatRemoteDataSource remoteDataSource;
  final ChatCipherService cipherService;
  final KeyVerificationService keyVerificationService;
  final PrivateConversationSecurityCoordinator
  privateConversationSecurityCoordinator;
  final AppDatabase _database;
  final LocalDataProtector _localDataProtector;
  final ChatRealtimeService? realtimeService;
  final OutboxStore outboxStore;
  final Map<int, AppUser> _usersById = {};
  final Map<int, Conversation> _conversationsById = {};
  final Map<int, List<ChatMessage>> _messageCacheByConversation = {};
  final Map<int, int> _lastMessageIdByConversation = {};
  DateTime? _lastConversationSyncAt;
  int? _activeCurrentUserId;
  int _activeWorkspaceId = 0;

  void setActiveWorkspaceId(int workspaceId) {
    if (_activeWorkspaceId == workspaceId) {
      return;
    }
    _activeWorkspaceId = workspaceId;
    _conversationsById.clear();
    _messageCacheByConversation.clear();
    _lastMessageIdByConversation.clear();
    _lastConversationSyncAt = null;
  }

  Future<List<AppUser>> fetchUsers() async {
    final users = await remoteDataSource.fetchUsers();
    _usersById
      ..clear()
      ..addEntries(users.map((user) => MapEntry(user.id, user)));
    return users;
  }

  Future<List<Conversation>> fetchConversations({
    required int currentUserId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    final conversations = await remoteDataSource.fetchConversations(
      updatedAfter: _lastConversationSyncAt,
    );
    _lastConversationSyncAt = DateTime.now().toUtc();
    for (final conversation in conversations) {
      final preview = conversation.lastMessagePreview.isEmpty
          ? ''
          : await _decryptPayloadWithUserRefresh(
              conversation: conversation,
              currentUserId: currentUserId,
              payload: conversation.lastMessagePreview,
            );
      final merged = conversation.copyWith(
        lastMessagePreview: preview.length > 80
            ? preview.substring(0, 80)
            : preview,
      );
      await _persistConversation(merged);
    }
    final rows = await _readVisibleConversationRows();
    final all = <Conversation>[];
    for (final row in rows) {
      all.add(await _mapConversationRow(row));
    }
    return all;
  }

  Future<Conversation> openPrivateConversation(int otherUserId) async {
    final conversation = await remoteDataSource.openPrivateConversation(
      otherUserId,
    );
    await _persistConversation(conversation);
    return conversation;
  }

  Future<List<ChatMessage>> fetchMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _refreshPrivateUsersIfNeeded(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    await flushPendingMessages(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    final existingRows = await _database.readMessagesForConversation(
      conversation.id,
    );
    final syncState = await _database.readSyncState(conversation.id);
    final deltaAfterId = existingRows.isEmpty
        ? null
        : syncState?.lastMessageId ??
              _lastMessageIdByConversation[conversation.id];
    var messages = await remoteDataSource.fetchMessages(
      conversation.id,
      afterId: deltaAfterId,
    );
    if (messages.isEmpty && existingRows.isEmpty && deltaAfterId != null) {
      messages = await remoteDataSource.fetchMessages(conversation.id);
    }
    final unprotectedExistingRows = <MessagesTableData>[];
    for (final row in existingRows) {
      unprotectedExistingRows.add(await _unprotectMessageRow(row));
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
        message: message,
        existingById: existingById,
        existingByClientId: existingByClientId,
      );
      await _database.upsertMessage(
        MessagesTableCompanion(
          id: drift.Value(message.id),
          conversationId: drift.Value(message.conversationId),
          senderId: drift.Value(message.senderId),
          senderName: drift.Value(message.senderName),
          plaintextBody: drift.Value(
            await _localDataProtector.protect(plaintext),
          ),
          encryptedBody: drift.Value(message.body),
          attachmentsJson: drift.Value(_encodeAttachments(message.attachments)),
          messageType: drift.Value(message.messageType),
          attachmentCount: drift.Value(message.attachmentCount),
          clientMessageId: drift.Value(message.clientMessageId),
          deliveryState: drift.Value(
            _deliveryStateToStored(message.deliveryState),
          ),
          failureReason: drift.Value(message.failureReason),
          isPending: const drift.Value(false),
          createdAt: drift.Value(message.createdAt),
        ),
      );
    }
    if (messages.isNotEmpty) {
      _lastMessageIdByConversation[conversation.id] = messages.last.id;
      await _database.upsertSyncState(
        ConversationSyncStateTableCompanion(
          conversationId: drift.Value(conversation.id),
          lastMessageId: drift.Value(messages.last.id),
          lastSyncedAt: drift.Value(DateTime.now().toUtc()),
        ),
      );
    }
    await _retryStoredDecryptErrors(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    final pending = await outboxStore.readForConversation(conversation.id);
    final mergedRemoteRows = await _database.readMessagesForConversation(
      conversation.id,
    );
    final mergedRemote = <ChatMessage>[];
    for (final row in mergedRemoteRows) {
      mergedRemote.add(await _mapMessageRow(row));
    }
    _messageCacheByConversation[conversation.id] = mergedRemote;
    return _mergeMessages(mergedRemote, pending);
  }

  Future<ChatMessage> sendMessage(
    Conversation conversation, {
    required int currentUserId,
    required String text,
    String messageType = 'text',
    List<PendingAttachmentUpload> attachments = const [],
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    await _refreshUsersForSecureSend();
    await _refreshPrivateUsersIfNeeded(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    await privateConversationSecurityCoordinator.prepareForSend(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
      onUserUpdated: (user) {
        _usersById[user.id] = user;
      },
    );
    final now = DateTime.now().toUtc();
    final uploadedAttachments = <ChatAttachment>[];
    for (final attachment in attachments) {
      uploadedAttachments.add(
        await remoteDataSource.uploadAttachment(
          conversation.id,
          filename: attachment.filename,
          bytes: attachment.bytes,
          mimeType: attachment.mimeType,
        ),
      );
    }
    final clientMessageId =
        '${conversation.id}_${currentUserId}_${now.microsecondsSinceEpoch}';
    final currentUser = _usersById[currentUserId];
    final queued = QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: conversation.id,
      senderId: currentUserId,
      senderName: currentUser?.displayName ?? 'You',
      plaintext: text,
      createdAt: now,
      deliveryState: MessageDeliveryState.pending,
    );
    await outboxStore.upsert(queued);

    try {
      final sent = await _sendQueuedMessage(
        queued,
        conversation: conversation,
        currentUserId: currentUserId,
        messageType: uploadedAttachments.isEmpty ? 'text' : messageType,
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
  }) async {
    final queued = await outboxStore.readForConversation(conversation.id);
    final target = queued.where(
      (item) => item.clientMessageId == clientMessageId,
    );
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
    );
  }

  Future<void> _ensureUsersLoaded() async {
    if (_usersById.isNotEmpty) {
      return;
    }
    await fetchUsers();
  }

  Future<void> _refreshUsersForSecureSend() async {
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
    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    if (peerUserId < 0) {
      return;
    }
    final peerUser = _usersById[peerUserId];
    if (peerUser?.preferredPqcDevice != null) {
      return;
    }
    await fetchUsers();
  }

  Future<String> _encryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required String plaintext,
  }) async {
    try {
      return await cipherService.encrypt(
        context: _cryptoContext(
          currentUserId: currentUserId,
          conversation: conversation,
        ),
        plaintext: plaintext,
      );
    } catch (error) {
      if (error is! ChatEncryptionException ||
          conversation.isGroup ||
          error.message != _peerPqcKeyNotReadyMessage) {
        rethrow;
      }
      await fetchUsers();
      return cipherService.encrypt(
        context: _cryptoContext(
          currentUserId: currentUserId,
          conversation: conversation,
        ),
        plaintext: plaintext,
      );
    }
  }

  Future<String> _decryptPayloadWithUserRefresh({
    required Conversation conversation,
    required int currentUserId,
    required String payload,
  }) async {
    final plaintext = await cipherService.decrypt(
      context: _cryptoContext(
        currentUserId: currentUserId,
        conversation: conversation,
      ),
      payload: payload,
    );
    if (conversation.isGroup || plaintext != '[decrypt-error]') {
      return plaintext;
    }
    await fetchUsers();
    return cipherService.decrypt(
      context: _cryptoContext(
        currentUserId: currentUserId,
        conversation: conversation,
      ),
      payload: payload,
    );
  }

  Future<String> _resolveMessagePlaintext({
    required Conversation conversation,
    required int currentUserId,
    required ChatMessage message,
    required Map<int, MessagesTableData> existingById,
    required Map<String, MessagesTableData> existingByClientId,
  }) async {
    final plaintext = await _decryptPayloadWithUserRefresh(
      conversation: conversation,
      currentUserId: currentUserId,
      payload: message.body,
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
  }) async {
    final rows = await _database.readMessagesForConversation(conversation.id);
    for (final row in rows) {
      final unprotectedRow = await _unprotectMessageRow(row);
      if (unprotectedRow.plaintextBody != '[decrypt-error]' ||
          unprotectedRow.encryptedBody.isEmpty) {
        continue;
      }
      final plaintext = await _decryptPayloadWithUserRefresh(
        conversation: conversation,
        currentUserId: currentUserId,
        payload: unprotectedRow.encryptedBody,
      );
      if (plaintext == '[decrypt-error]') {
        continue;
      }
      await _database.upsertMessage(
        MessagesTableCompanion(
          id: drift.Value(unprotectedRow.id),
          conversationId: drift.Value(unprotectedRow.conversationId),
          senderId: drift.Value(unprotectedRow.senderId),
          senderName: drift.Value(unprotectedRow.senderName),
          plaintextBody: drift.Value(
            await _localDataProtector.protect(plaintext),
          ),
          encryptedBody: drift.Value(unprotectedRow.encryptedBody),
          attachmentsJson: drift.Value(unprotectedRow.attachmentsJson),
          messageType: drift.Value(unprotectedRow.messageType),
          attachmentCount: drift.Value(unprotectedRow.attachmentCount),
          clientMessageId: drift.Value(unprotectedRow.clientMessageId),
          deliveryState: drift.Value(unprotectedRow.deliveryState),
          failureReason: drift.Value(unprotectedRow.failureReason),
          isPending: drift.Value(unprotectedRow.isPending),
          createdAt: drift.Value(unprotectedRow.createdAt),
        ),
      );
    }
  }

  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    String messageType = 'text',
    List<int> attachmentIds = const [],
  }) async {
    final payload = queued.encryptedPayload.isNotEmpty
        ? queued.encryptedPayload
        : await _encryptPayloadWithUserRefresh(
            conversation: conversation,
            currentUserId: currentUserId,
            plaintext: queued.plaintext,
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
              payload: message.body,
            ),
      createdAt: message.createdAt,
      messageType: message.messageType,
      attachmentCount: message.attachmentCount,
      attachments: message.attachments,
      clientMessageId: message.clientMessageId,
      deliveryState: MessageDeliveryState.sent,
    );
    await _database.upsertMessage(
      MessagesTableCompanion(
        id: drift.Value(decoded.id),
        conversationId: drift.Value(decoded.conversationId),
        senderId: drift.Value(decoded.senderId),
        senderName: drift.Value(decoded.senderName),
        plaintextBody: drift.Value(
          await _localDataProtector.protect(decoded.body),
        ),
        encryptedBody: drift.Value(message.body),
        attachmentsJson: drift.Value(_encodeAttachments(decoded.attachments)),
        messageType: drift.Value(decoded.messageType),
        attachmentCount: drift.Value(decoded.attachmentCount),
        clientMessageId: drift.Value(decoded.clientMessageId),
        deliveryState: drift.Value(
          _deliveryStateToStored(decoded.deliveryState),
        ),
        failureReason: drift.Value(decoded.failureReason),
        isPending: const drift.Value(false),
        createdAt: drift.Value(decoded.createdAt),
      ),
    );
    await _persistConversation(
      conversation.copyWith(
        lastMessagePreview: decoded.body.length > 80
            ? decoded.body.substring(0, 80)
            : decoded.body,
        updatedAt: decoded.createdAt,
      ),
    );
    return decoded;
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

  Future<Map<int, UserKeyTrust>> buildUserTrustMap() async {
    await _ensureUsersLoaded();
    return keyVerificationService.buildUserTrustMap(_usersById.values);
  }

  Future<ConversationKeyTrust> getConversationTrust({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    return keyVerificationService.getConversationTrust(
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
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
    final peerUser = trust.peerUser;
    if (peerUser == null) {
      return;
    }
    await keyVerificationService.verifyUser(peerUser);
  }

  ChatCryptoContext _cryptoContext({
    required int currentUserId,
    required Conversation conversation,
  }) {
    return ChatCryptoContext(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
  }

  Future<void> _handleRealtimeEvent(ChatRealtimeEvent event) async {
    if (event.event == 'conversation.updated') {
      return;
    }
    if (event.event != 'message.created') {
      return;
    }
    final conversationId = event.payload['conversation_id'] as int?;
    if (conversationId == null) {
      return;
    }
    final knownConversation = _conversationsById[conversationId];
    if (knownConversation == null) {
      return;
    }
    final currentUserId = _activeCurrentUserId;
    if (currentUserId == null) {
      return;
    }
    final payload = event.payload['body'] as String? ?? '';
    final plaintext = await _decryptPayloadWithUserRefresh(
      conversation: knownConversation,
      currentUserId: currentUserId,
      payload: payload,
    );
    await _database.upsertMessage(
      MessagesTableCompanion(
        id: drift.Value(event.payload['id'] as int),
        conversationId: drift.Value(conversationId),
        senderId: drift.Value(event.payload['sender_id'] as int),
        senderName: drift.Value(event.payload['sender_name'] as String? ?? ''),
        plaintextBody: drift.Value(
          await _localDataProtector.protect(plaintext),
        ),
        encryptedBody: drift.Value(payload),
        attachmentsJson: drift.Value(
          _encodeAttachments(
            (event.payload['attachments'] as List<dynamic>? ?? const [])
                .map(
                  (item) =>
                      ChatAttachment.fromJson(item as Map<String, dynamic>),
                )
                .toList(),
          ),
        ),
        messageType: drift.Value(
          event.payload['message_type'] as String? ?? 'text',
        ),
        attachmentCount: drift.Value(
          event.payload['attachment_count'] as int? ?? 0,
        ),
        clientMessageId: drift.Value(
          event.payload['client_message_id'] as String? ?? '',
        ),
        deliveryState: drift.Value(
          _deliveryStateToStored(MessageDeliveryState.sent),
        ),
        failureReason: const drift.Value(null),
        isPending: const drift.Value(false),
        createdAt: drift.Value(
          DateTime.parse(event.payload['created_at'] as String),
        ),
      ),
    );
    await _persistConversation(
      knownConversation.copyWith(
        lastMessagePreview: plaintext.length > 80
            ? plaintext.substring(0, 80)
            : plaintext,
        updatedAt: DateTime.parse(event.payload['created_at'] as String),
      ),
    );
  }

  Future<void> _persistConversation(Conversation conversation) async {
    final effectiveWorkspaceId = conversation.workspaceId > 0
        ? conversation.workspaceId
        : _activeWorkspaceId;
    await _database.upsertConversation(
      ConversationsTableCompanion(
        id: drift.Value(conversation.id),
        workspaceId: drift.Value(effectiveWorkspaceId),
        type: drift.Value(conversation.type),
        title: drift.Value(conversation.title),
        lastMessagePreview: drift.Value(
          await _localDataProtector.protect(conversation.lastMessagePreview),
        ),
        updatedAt: drift.Value(conversation.updatedAt),
        createdAt: drift.Value(conversation.createdAt),
      ),
    );
    _conversationsById[conversation.id] = conversation.copyWith(
      workspaceId: effectiveWorkspaceId,
    );
  }

  Future<Conversation> _mapConversationRow(ConversationsTableData row) async {
    return Conversation(
      id: row.id,
      workspaceId: row.workspaceId,
      type: row.type,
      title: row.title,
      participantIds: _conversationsById[row.id]?.participantIds ?? const [],
      lastMessagePreview: await _localDataProtector.unprotect(
        row.lastMessagePreview,
      ),
      updatedAt: row.updatedAt,
      createdAt: row.createdAt,
    );
  }

  Future<ChatMessage> _mapMessageRow(MessagesTableData row) async {
    return ChatMessage(
      id: row.id,
      conversationId: row.conversationId,
      senderId: row.senderId,
      senderName: row.senderName,
      body: await _localDataProtector.unprotect(row.plaintextBody),
      createdAt: row.createdAt,
      attachments: _decodeAttachments(row.attachmentsJson),
      messageType: row.messageType,
      attachmentCount: row.attachmentCount,
      clientMessageId: row.clientMessageId,
      deliveryState: _deliveryStateFromStored(row.deliveryState),
      failureReason: row.failureReason,
    );
  }

  Future<MessagesTableData> _unprotectMessageRow(MessagesTableData row) async {
    return row.copyWith(
      plaintextBody: await _localDataProtector.unprotect(row.plaintextBody),
    );
  }

  Future<List<ConversationsTableData>> _readVisibleConversationRows() async {
    if (_activeWorkspaceId <= 0) {
      return _database.readConversations();
    }
    final scopedRows = await _database.readConversationsForWorkspace(
      _activeWorkspaceId,
    );
    if (scopedRows.isNotEmpty) {
      return scopedRows;
    }
    return _database.readConversations();
  }

  String _deliveryStateToStored(MessageDeliveryState state) => switch (state) {
    MessageDeliveryState.pending => 'pending',
    MessageDeliveryState.sent => 'sent',
    MessageDeliveryState.failedRetryable => 'failed-retryable',
    MessageDeliveryState.failedPermanent => 'failed-permanent',
  };

  MessageDeliveryState _deliveryStateFromStored(String value) {
    switch (value) {
      case 'failed-retryable':
        return MessageDeliveryState.failedRetryable;
      case 'failed-permanent':
        return MessageDeliveryState.failedPermanent;
      case 'pending':
        return MessageDeliveryState.pending;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }

  String _encodeAttachments(List<ChatAttachment> attachments) {
    return jsonEncode(
      attachments
          .map(
            (item) => {
              'id': item.id,
              'filename': item.filename,
              'mime_type': item.mimeType,
              'size_bytes': item.sizeBytes,
              'storage_key': item.storageKey,
              'thumbnail_key': item.thumbnailKey,
              'created_at': item.createdAt?.toIso8601String(),
            },
          )
          .toList(),
    );
  }

  List<ChatAttachment> _decodeAttachments(String raw) {
    if (raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((item) => ChatAttachment.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}

class PendingAttachmentUpload {
  const PendingAttachmentUpload({
    required this.filename,
    required this.bytes,
    required this.mimeType,
  });

  final String filename;
  final List<int> bytes;
  final String mimeType;
}
