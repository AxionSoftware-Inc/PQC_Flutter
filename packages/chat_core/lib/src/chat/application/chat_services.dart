// ignore_for_file: implementation_imports

import 'dart:async';

import '../../core/database/app_database.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/attachment_transfer.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import '../../core/network/api_client.dart';
import 'package:crypto_core/src/crypto/chat_cipher_service.dart';
import 'package:crypto_core/src/crypto/attachment_crypto_service.dart';
import 'package:crypto_core/src/crypto/chat_crypto_context.dart';
import 'package:crypto_core/src/crypto/chat_crypto_exceptions.dart';
import 'package:crypto_core/src/crypto/durability/crypto_core_facade.dart';
import 'package:crypto_core/src/crypto/durability/crypto_durability_models.dart';
import '../../security/key_verification_service.dart';
import '../../transfer/attachment_transfer.dart';
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
    this.messageId = '',
  });

  final int currentUserId;
  final Conversation conversation;
  final Map<int, AppUser> usersById;
  final String messageId;
}

class ChatCryptoService {
  static const peerPqcKeyNotReadyMessage =
      'Peer PQC device key is not ready yet. Ask them to reopen the app.';
  static const decryptErrorMarker = '[decrypt-error]';
  static const decryptNeedsBackupRestoreMarker =
      '[decrypt-needs-backup-restore]';
  static const decryptKeyMissingMarker = '[decrypt-key-missing]';
  static const decryptHistoryRecoveryPendingMarker =
      '[history-recovery-pending]';

  const ChatCryptoService({required this.cipherService, this.cryptoCoreFacade});

  final ChatCipherService cipherService;
  final CryptoCoreFacade? cryptoCoreFacade;

  Future<String> encrypt({
    required ChatCryptoRequest request,
    required String plaintext,
  }) {
    return cipherService.encrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
        messageId: request.messageId,
      ),
      plaintext: plaintext,
    );
  }

  Future<void> assertRemoteCanSend({
    required bool isGroup,
    required Iterable<String> remotePrefixes,
  }) async {
    final facade = cryptoCoreFacade;
    if (facade == null) {
      // The server capability gate still protects the wire protocol. Older
      // repository integrations may not expose the optional durability
      // facade, so message sending remains compatible for text payloads.
      return;
    }
    facade.assertRemoteSupportsActiveMessageWriter(
      isGroup: isGroup,
      remotePrefixes: remotePrefixes,
    );
  }

  Future<AttachmentEncryptionDescriptor> deriveAttachmentDescriptor({
    required ChatCryptoRequest request,
    required String attachmentId,
  }) async {
    final facade = cryptoCoreFacade;
    if (facade == null) {
      throw StateError('Crypto durability core is required for attachments.');
    }
    if (request.conversation.isGroup) {
      final epoch = await facade.groupKeyStore.getOrCreateKey(
        conversation: request.conversation,
        usersById: request.usersById,
      );
      return AttachmentCryptoService().deriveEpochBoundDescriptor(
        conversationEpochSecret: epoch.secretKeyBytes,
        conversationEpochId: epoch.keyId,
        attachmentId: attachmentId,
        manifestSequence: 0,
      );
    }
    final epoch = await facade.conversationEpochKeyStore
        .getOrCreatePrivateEpoch(request.conversation.id);
    return AttachmentCryptoService().deriveEpochBoundDescriptor(
      conversationEpochSecret: epoch.secretKeyBytes,
      conversationEpochId: epoch.epochId,
      attachmentId: attachmentId,
      manifestSequence: 0,
    );
  }

  Future<String> decrypt({
    required ChatCryptoRequest request,
    required String payload,
  }) async {
    final outcome = await decryptDetailed(request: request, payload: payload);
    return switch (outcome) {
      DecryptSuccess(:final plaintext) => plaintext,
      DecryptNeedsBackupRestore() => decryptNeedsBackupRestoreMarker,
      DecryptKeyMissing() => decryptKeyMissingMarker,
      DecryptFormatUnsupported() => decryptErrorMarker,
      DecryptCorruptedPayload() => decryptErrorMarker,
      _ => decryptErrorMarker,
    };
  }

  bool isDecryptFailureMarker(String value) {
    return value == decryptErrorMarker ||
        value == decryptNeedsBackupRestoreMarker ||
        value == decryptKeyMissingMarker ||
        value == decryptHistoryRecoveryPendingMarker;
  }

  Future<DecryptionOutcome> decryptDetailed({
    required ChatCryptoRequest request,
    required String payload,
  }) async {
    final plaintext = await cipherService.decrypt(
      context: ChatCryptoContext(
        currentUserId: request.currentUserId,
        conversation: request.conversation,
        usersById: request.usersById,
        messageId: request.messageId,
      ),
      payload: payload,
    );
    final cryptoCoreFacade = this.cryptoCoreFacade;
    if (cryptoCoreFacade == null) {
      if (!isDecryptFailureMarker(plaintext)) {
        return DecryptSuccess(
          plaintext: plaintext,
          format: const PayloadFormatDescriptor(
            formatId: 'legacy-pass-through',
            payloadKind: PayloadKind.privateMessage,
            prefix: '',
            introducedAtVersion: '0.0.0',
            decryptSupported: true,
          ),
        );
      }
      return DecryptCorruptedPayload(
        format: const PayloadFormatDescriptor(
          formatId: 'legacy-unknown',
          payloadKind: PayloadKind.privateMessage,
          prefix: '',
          introducedAtVersion: '0.0.0',
          decryptSupported: true,
        ),
      );
    }
    final format = cryptoCoreFacade.describePayload(payload);
    if (!isDecryptFailureMarker(plaintext)) {
      return DecryptSuccess(
        plaintext: plaintext,
        format:
            format ??
            const PayloadFormatDescriptor(
              formatId: 'plaintext-pass-through',
              payloadKind: PayloadKind.privateMessage,
              prefix: '',
              introducedAtVersion: '0.0.0',
              decryptSupported: true,
            ),
      );
    }
    return cryptoCoreFacade.classifyFailedDecrypt(payload);
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

  Future<Map<int, UserKeyTrust>> buildUserTrustMap(Iterable<AppUser> users) {
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
    if (conversation.isGroup ||
        !cryptoService.isDecryptFailureMarker(plaintext)) {
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
    if (conversation.isGroup ||
        !cryptoService.isDecryptFailureMarker(plaintext)) {
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

class OutgoingMessageService {
  const OutgoingMessageService({
    required this.remoteDataSource,
    required this.cryptoService,
    required this.localStore,
    required this.outboxStore,
    this.attachmentTransferFacade,
    this.onCryptoStateChanged,
  });

  final ChatRemoteDataSource remoteDataSource;
  final ChatCryptoService cryptoService;
  final ChatLocalStore localStore;
  final OutboxStore outboxStore;
  final AttachmentTransferFacade? attachmentTransferFacade;
  final Future<void> Function()? onCryptoStateChanged;

  Future<ChatMessage> sendMessage({
    required SendMessageCommand command,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
  }) async {
    final now = DateTime.now().toUtc();
    final clientMessageId =
        '${command.conversation.id}_${command.currentUserId}_${now.microsecondsSinceEpoch}';
    final currentUser = usersById[command.currentUserId];
    final queued = QueuedOutgoingMessage(
      clientMessageId: clientMessageId,
      conversationId: command.conversation.id,
      senderId: command.currentUserId,
      senderName: currentUser?.displayName ?? 'You',
      plaintext: command.text,
      messageType: command.messageType,
      attachments: command.attachments,
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
      );
      final cryptoStateChanged = onCryptoStateChanged;
      if (cryptoStateChanged != null) {
        unawaited(cryptoStateChanged());
      }
      await outboxStore.remove(clientMessageId);
      return sent;
    } on ApiException catch (error) {
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
    required Future<void> Function(Conversation conversation)
    persistConversation,
    bool includeAttachments = false,
  }) async {
    final pending = await outboxStore.readForConversation(conversation.id);
    for (final item in pending) {
      // File sends are explicit user actions. Retrying them automatically on
      // every login/chat refresh can replay large uploads and block history.
      if (!includeAttachments && item.attachments.isNotEmpty) {
        continue;
      }
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
    required Future<void> Function(Conversation conversation)
    persistConversation,
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
      usersById: usersById,
      refreshUsers: refreshUsers,
      persistConversation: persistConversation,
      includeAttachments: true,
    );
  }

  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required Future<void> Function() refreshUsers,
    required Future<void> Function(Conversation conversation)
    persistConversation,
  }) async {
    final capabilities = await remoteDataSource
        .fetchCryptoProtocolCapabilities();
    try {
      await cryptoService.assertRemoteCanSend(
        isGroup: conversation.isGroup,
        remotePrefixes: conversation.isGroup
            ? capabilities.groupMessagePrefixes
            : capabilities.privateMessagePrefixes,
      );
    } on StateError catch (error) {
      // A protocol mismatch is permanent for this queued payload. Persist it
      // as a delivery failure instead of allowing a crypto assertion to escape
      // through the UI event loop.
      throw ApiException(
        error.message,
        code: 'crypto_protocol_mismatch',
        isRetryable: false,
      );
    }
    final attachmentIds = <int>[];
    for (final attachment in queued.attachments) {
      if (!attachment.hasUploadSource) {
        throw ApiException(
          'Attachment source is missing. Please pick the file again.',
          code: 'attachment_source_missing',
          isRetryable: false,
        );
      }
      // Keep attachments deliberately simple for v2: one multipart request
      // per file. Message encryption remains unchanged; the resumable chunk
      // engine is not involved in normal chat sends.
      final uploaded = await remoteDataSource.uploadAttachment(
        conversation.id,
        filename: attachment.filename,
        bytes: attachment.bytes,
        filePath: attachment.filePath,
        mimeType: attachment.mimeType,
      );
      attachmentIds.add(uploaded.id);
    }
    final payload = queued.encryptedPayload.isNotEmpty
        ? queued.encryptedPayload
        : await _encryptPayloadWithUserRefresh(
            conversation: conversation,
            currentUserId: currentUserId,
            usersById: usersById,
            plaintext: queued.plaintext,
            messageId: queued.clientMessageId,
            refreshUsers: refreshUsers,
          );
    if (queued.encryptedPayload.isEmpty) {
      await outboxStore.upsert(queued.copyWith(encryptedPayload: payload));
    }
    final message = await remoteDataSource.sendMessage(
      conversation.id,
      payload,
      clientMessageId: queued.clientMessageId,
      messageType: attachmentIds.isEmpty ? 'text' : queued.messageType,
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
    await localStore.persistMessage(
      decoded: decoded,
      encryptedBody: message.body,
    );
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
    required String messageId,
    required Future<void> Function() refreshUsers,
  }) async {
    try {
      return await cryptoService.encrypt(
        request: ChatCryptoRequest(
          currentUserId: currentUserId,
          conversation: conversation,
          usersById: usersById,
          messageId: messageId,
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
          messageId: messageId,
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
    if (conversation.isGroup ||
        !cryptoService.isDecryptFailureMarker(plaintext)) {
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
    required Future<void> Function(Conversation conversation)
    persistConversation,
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
    if (conversation.isGroup ||
        !cryptoService.isDecryptFailureMarker(plaintext)) {
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
