// ignore_for_file: prefer_initializing_formals, use_super_parameters

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

part 'chat_facade_users.dart';
part 'chat_facade_conversations.dart';
part 'chat_facade_messaging.dart';
part 'chat_facade_attachments.dart';
part 'chat_facade_realtime.dart';

abstract class _ChatFacadeBase {
  _ChatFacadeBase({
    required ChatRemoteDataSource remoteDataSource,
    required ChatRealtimeService? realtimeService,
    required OutboxStore outboxStore,
    required ChatLocalStore localStore,
    required ChatTrustService trustService,
    required ChatCryptoService cryptoService,
    ConversationDevicePolicy? devicePolicy,
    ConversationSyncService? conversationSyncService,
    MessageSyncService? messageSyncService,
    OutgoingMessageService? outgoingMessageService,
    Future<void> Function()? onCryptoStateChanged,
    AttachmentTransferFacade? attachmentTransferFacade,
    ChatRealtimeCoordinator? realtimeCoordinator,
  }) : _trustService = trustService,
       _remoteDataSource = remoteDataSource,
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

  Future<List<AppUser>> fetchUsers();

  Future<void> _ensureUsersLoaded();

  Future<void> _refreshUsersForSecureSend();

  Future<void> _refreshPrivateUsersIfNeeded({
    required Conversation conversation,
    required int currentUserId,
  });

  Future<void> _persistConversation(Conversation conversation);

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

  Future<void> _handleRealtimeEvent(ChatRealtimeEvent event);
}

class ChatFacade extends _ChatFacadeBase
    with
        _ChatFacadeUsers,
        _ChatFacadeConversations,
        _ChatFacadeMessaging,
        _ChatFacadeAttachments,
        _ChatFacadeRealtime {
  ChatFacade({
    required ChatRemoteDataSource remoteDataSource,
    required ChatRealtimeService? realtimeService,
    required OutboxStore outboxStore,
    required ChatLocalStore localStore,
    required ChatTrustService trustService,
    required ChatCryptoService cryptoService,
    ConversationDevicePolicy? devicePolicy,
    ConversationSyncService? conversationSyncService,
    MessageSyncService? messageSyncService,
    OutgoingMessageService? outgoingMessageService,
    Future<void> Function()? onCryptoStateChanged,
    AttachmentTransferFacade? attachmentTransferFacade,
    ChatRealtimeCoordinator? realtimeCoordinator,
  }) : super(
         remoteDataSource: remoteDataSource,
         realtimeService: realtimeService,
         outboxStore: outboxStore,
         localStore: localStore,
         trustService: trustService,
         cryptoService: cryptoService,
         devicePolicy: devicePolicy,
         conversationSyncService: conversationSyncService,
         messageSyncService: messageSyncService,
         outgoingMessageService: outgoingMessageService,
         onCryptoStateChanged: onCryptoStateChanged,
         attachmentTransferFacade: attachmentTransferFacade,
         realtimeCoordinator: realtimeCoordinator,
       );
}
