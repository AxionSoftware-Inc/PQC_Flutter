import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_core/crypto_core.dart';
import '../../core/network/api_client.dart';
import '../../transfer/attachment_transfer.dart';
import '../../security/key_verification_service.dart';
import '../data/chat_remote_data_source.dart';
import '../data/chat_realtime_service.dart';
import '../data/outbox_store.dart';
import 'chat_local_store.dart';
import 'chat_models.dart';
import 'chat_services.dart';
import 'conversation_device_policy.dart';

class ChatFacade {
  ChatFacade({
    required ChatRemoteDataSource remoteDataSource,
    required ChatRealtimeService? realtimeService,
    required OutboxStore outboxStore,
    required ChatLocalStore localStore,
    required this._trustService,
    required ChatCryptoService cryptoService,
    ConversationDevicePolicy? devicePolicy,
    ConversationSyncService? conversationSyncService,
    MessageSyncService? messageSyncService,
    OutgoingMessageService? outgoingMessageService,
    Future<void> Function()? onCryptoStateChanged,
    AttachmentTransferFacade? attachmentTransferFacade,
    ChatRealtimeCoordinator? realtimeCoordinator,
  }) : _remoteDataSource = remoteDataSource,
       _cryptoService = cryptoService,
       _outboxStore = outboxStore,
       _localStore = localStore,
       _devicePolicy = devicePolicy ?? const ConversationDevicePolicy(),
       _conversationSyncService =
           conversationSyncService ??
           ConversationSyncService(
             remoteDataSource: remoteDataSource,
             cryptoService: cryptoService,
           ),
       _messageSyncService =
           messageSyncService ??
           MessageSyncService(
             remoteDataSource: remoteDataSource,
             localStore: localStore,
             cryptoService: cryptoService,
           ),
       _outgoingMessageService =
           outgoingMessageService ??
           OutgoingMessageService(
             remoteDataSource: remoteDataSource,
             cryptoService: cryptoService,
             localStore: localStore,
             outboxStore: outboxStore,
             attachmentTransferFacade: attachmentTransferFacade,
             onCryptoStateChanged: onCryptoStateChanged,
           ),
       _attachmentTransferFacade = attachmentTransferFacade,
       _realtimeCoordinator =
           realtimeCoordinator ??
           ChatRealtimeCoordinator(
             localStore: localStore,
             cryptoService: cryptoService,
           ),
       _realtimeService = realtimeService {
    realtimeService?.events.listen((event) {
      _realtimeEvents.add(event);
      unawaited(_handleRealtimeEvent(event));
    });
  }

  final StreamController<ChatRealtimeEvent> _realtimeEvents =
      StreamController<ChatRealtimeEvent>.broadcast();

  Stream<ChatRealtimeEvent> get realtimeEvents => _realtimeEvents.stream;

  void sendRealtimeEvent(String event, Map<String, dynamic> payload) {
    _realtimeService?.sendEvent(event, payload);
  }

  final ChatRemoteDataSource _remoteDataSource;
  final ChatCryptoService _cryptoService;
  final OutboxStore _outboxStore;
  final ChatLocalStore _localStore;
  final ChatTrustService _trustService;
  final ConversationDevicePolicy _devicePolicy;
  final ConversationSyncService _conversationSyncService;
  final MessageSyncService _messageSyncService;
  final OutgoingMessageService _outgoingMessageService;
  final AttachmentTransferFacade? _attachmentTransferFacade;
  final ChatRealtimeCoordinator _realtimeCoordinator;
  final ChatRealtimeService? _realtimeService;

  final Map<int, AppUser> _usersById = {};
  Future<List<AppUser>>? _usersFetchInFlight;
  DateTime? _lastSecureSendUsersRefreshAt;
  Future<void>? _secureUsersRefreshInFlight;
  final Map<int, DateTime> _privateUsersRefreshAt = {};
  final Map<int, Conversation> _conversationsById = {};
  final Map<int, int> _lastMessageIdByConversation = {};
  DateTime? _lastConversationSyncAt;
  int? _activeCurrentUserId;
  int _activeWorkspaceId = 0;

  ValueListenable<List<AttachmentTransferState>>? get attachmentTransfers =>
      _attachmentTransferFacade?.transfers;

  void switchWorkspaceContext(int workspaceId) {
    if (_activeWorkspaceId == workspaceId) {
      return;
    }
    _activeWorkspaceId = workspaceId;
    _conversationsById.clear();
    _lastMessageIdByConversation.clear();
    _lastConversationSyncAt = null;
  }

  Future<List<AppUser>> fetchUsers() {
    final inFlight = _usersFetchInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<List<AppUser>> operation;
    operation = _fetchUsersOnce();
    _usersFetchInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_usersFetchInFlight, operation)) {
        _usersFetchInFlight = null;
      }
    });
  }

  Future<List<AppUser>> _fetchUsersOnce() async {
    final users = await _remoteDataSource.fetchUsers();
    _usersById
      ..clear()
      ..addEntries(users.map((user) => MapEntry(user.id, user)));
    _lastSecureSendUsersRefreshAt = DateTime.now();
    return users;
  }

  /// Optional RBAC integration. The core chat flow stays independent of this
  /// endpoint; deployments without the RBAC plugin simply never expose the
  /// management action in the UI.
  Future<AppUser> updateUserRole({
    required int userId,
    required String role,
  }) async {
    final user = await _remoteDataSource.updateUserRole(userId, role);
    _usersById[user.id] = user;
    return user;
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

  Future<ChatMessage> forwardMessage(int messageId, int conversationId) {
    return _remoteDataSource.forwardMessage(messageId, conversationId);
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

  Future<List<AttachmentTransferState>> loadAttachmentTransfers() async {
    final transferFacade = _attachmentTransferFacade;
    if (transferFacade == null) {
      return const [];
    }
    return transferFacade.loadTransfers();
  }

  Future<void> pauseAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.pauseTransfer(localId);
  }

  Future<AttachmentTransferState?> resumeAttachmentTransfer({
    required String localId,
    required Conversation conversation,
    required int currentUserId,
  }) async {
    final transferFacade = _attachmentTransferFacade;
    if (transferFacade == null) {
      return null;
    }
    final resumed = await transferFacade.resumeTransfer(localId);
    if (resumed == null ||
        resumed.direction != AttachmentTransferDirection.upload) {
      return resumed;
    }
    final marker = ':attachment:';
    final markerIndex = localId.indexOf(marker);
    if (markerIndex <= 0) return resumed;
    await _outgoingMessageService.retryMessage(
      conversation: conversation,
      currentUserId: currentUserId,
      clientMessageId: localId.substring(0, markerIndex),
      usersById: _usersById,
      refreshUsers: _refreshUsersForSecureSend,
      persistConversation: _persistConversation,
    );
    return resumed;
  }

  Future<void> cancelAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.cancelTransfer(localId);
  }

  Future<void> clearCompletedAttachmentTransfer(String localId) async {
    await _attachmentTransferFacade?.clearCompletedTransfer(localId);
  }

  Future<String> downloadAttachment({
    required int currentUserId,
    required Conversation conversation,
    required ChatAttachment attachment,
  }) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    if (attachment.cipherVersion == 'attachment:v2' ||
        attachment.cipherVersion == 'attachment:v3') {
      final descriptor = await _remoteDataSource.fetchAttachmentDescriptor(
        attachment.id,
      );
      final request = ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: _usersById,
        messageId: 'attachment-download:${attachment.id}',
      );
      final encryptionDescriptor = await _cryptoService
          .decryptAttachmentKeyWrap(
            request: request,
            wrappedDescriptor: descriptor.fileKeyWrap,
          );
      if (encryptionDescriptor.cipherVersion != descriptor.cipherVersion) {
        throw StateError('Attachment cipher descriptor does not match data.');
      }
      final cryptoAdapter = switch (descriptor.cipherVersion) {
        'attachment:v3' => SdkV3AttachmentCryptoService(),
        'attachment:v2' => SdkV2AttachmentCryptoService(),
        _ => throw StateError('Unsupported attachment cipher version.'),
      };
      if (descriptor.chunkSize <= 0 || descriptor.plaintextSize <= 0) {
        throw StateError('Encrypted attachment manifest is incomplete.');
      }
      final totalChunks =
          (descriptor.plaintextSize + descriptor.chunkSize - 1) ~/
          descriptor.chunkSize;
      final transferLocalId = 'download:${descriptor.id}';
      await _attachmentTransferFacade?.beginDownload(
        localId: transferLocalId,
        conversationId: conversation.id,
        filename: descriptor.filename,
        totalChunks: totalChunks,
        attachmentId: descriptor.id,
      );
      final builder = BytesBuilder(copy: false);
      try {
        for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
          await _attachmentTransferFacade?.throwIfPaused(transferLocalId);
          final ciphertext = await _remoteDataSource.downloadAttachmentChunk(
            attachmentId: descriptor.id,
            chunkIndex: chunkIndex,
          );
          builder.add(
            await cryptoAdapter.decryptChunk(
              ciphertext: ciphertext,
              descriptor: encryptionDescriptor,
              chunkIndex: chunkIndex,
            ),
          );
          await _attachmentTransferFacade?.updateDownloadProgress(
            localId: transferLocalId,
            completedChunks: chunkIndex + 1,
            totalChunks: totalChunks,
          );
        }
      } catch (error) {
        if (error is! AttachmentTransferPausedException) {
          await _attachmentTransferFacade?.failTransfer(transferLocalId, error);
        }
        rethrow;
      }
      final bytes = builder.takeBytes();
      if (bytes.length != descriptor.plaintextSize ||
          (descriptor.plaintextSha256.isNotEmpty &&
              crypto.sha256.convert(bytes).toString().toLowerCase() !=
                  descriptor.plaintextSha256.toLowerCase())) {
        throw StateError('Encrypted attachment integrity check failed.');
      }
      final transfer = await _attachmentTransferFacade?.saveDirectDownload(
        attachment: descriptor,
        bytes: bytes,
      );
      if (transfer != null) return transfer;
      throw StateError('Attachment download storage is not configured.');
    }
    final transferLocalId = 'download:${attachment.id}';
    await _attachmentTransferFacade?.beginDownload(
      localId: transferLocalId,
      conversationId: conversation.id,
      filename: attachment.filename,
      totalChunks: 1,
      attachmentId: attachment.id,
    );
    late final List<int> bytes;
    try {
      await _attachmentTransferFacade?.throwIfPaused(transferLocalId);
      bytes = await _remoteDataSource.downloadAttachmentFile(attachment.id);
      await _attachmentTransferFacade?.updateDownloadProgress(
        localId: transferLocalId,
        completedChunks: 1,
        totalChunks: 1,
      );
    } catch (error) {
      if (error is! AttachmentTransferPausedException) {
        await _attachmentTransferFacade?.failTransfer(transferLocalId, error);
      }
      rethrow;
    }
    final transfer = await _attachmentTransferFacade?.saveDirectDownload(
      attachment: attachment,
      bytes: bytes,
    );
    if (transfer != null) return transfer;
    throw StateError('Attachment download storage is not configured.');
  }

  Future<void> resumePendingWork({required int currentUserId}) async {
    _activeCurrentUserId = currentUserId;
    await _ensureUsersLoaded();
    if (_attachmentTransferFacade != null) {
      await _attachmentTransferFacade.resumePendingDownloads();
    }
    final rows = await _localStore.readVisibleConversationRows(
      _activeWorkspaceId,
    );
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
