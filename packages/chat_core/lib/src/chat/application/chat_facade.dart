// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
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

  Future<List<AppUser>> fetchUsers() async {
    final users = await _remoteDataSource.fetchUsers();
    _usersById
      ..clear()
      ..addEntries(users.map((user) => MapEntry(user.id, user)));
    return users;
  }

  Future<ChatListState> loadChatList({required int currentUserId}) async {
    _activeCurrentUserId = currentUserId;
    final users = await fetchUsers();
    final existingRows = await _localStore.readVisibleConversationRows(
      _activeWorkspaceId,
    );
    final syncResult = await _conversationSyncService.fetchConversations(
      currentUserId: currentUserId,
      usersById: _usersById,
      updatedAfter: _lastConversationSyncAt,
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

  Future<AttachmentTransferState?> resumeAttachmentTransfer(String localId) {
    final transferFacade = _attachmentTransferFacade;
    if (transferFacade == null) {
      return Future.value(null);
    }
    return transferFacade.resumeTransfer(localId);
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
    final bytes = await _remoteDataSource.downloadAttachmentFile(attachment.id);
    final transfer = await _attachmentTransferFacade?.saveDirectDownload(
      attachment: attachment,
      bytes: bytes,
    );
    if (transfer != null) return transfer;
    throw StateError('Attachment download storage is not configured.');
  }

  Future<Map<int, UserKeyTrust>> buildUserTrustMap() async {
    await _ensureUsersLoaded();
    return _trustService.buildUserTrustMap(_usersById.values);
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
    final resolution = _devicePolicy.resolvePrivatePeerPqcDevice(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
    if (resolution.isReady) {
      return;
    }
    await fetchUsers();
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
