// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import '../../security/key_verification_service.dart';
import '../../transfer/attachment_transfer.dart';
import 'chat_facade.dart';
import 'chat_models.dart';
import '../data/chat_realtime_service.dart';

class ChatListController extends ChangeNotifier {
  ChatListController({required this.chatFacade, required this.currentUserId});

  final ChatFacade chatFacade;
  final int currentUserId;

  bool _isLoading = true;
  String? _error;
  List<AppUser> _users = const [];
  List<Conversation> _conversations = const [];
  Map<int, UserKeyTrust> _trustByUserId = const {};

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<AppUser> get users => _users;
  List<Conversation> get conversations => _conversations;
  Map<int, UserKeyTrust> get trustByUserId => _trustByUserId;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final state = await chatFacade.loadChatList(currentUserId: currentUserId);
      _users = state.users;
      _conversations = state.conversations;
      _trustByUserId = state.trustByUserId;
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Conversation> openPrivateConversation(int otherUserId) {
    return chatFacade.openPrivateConversation(otherUserId);
  }

  void switchWorkspaceContext(int workspaceId) {
    chatFacade.switchWorkspaceContext(workspaceId);
  }
}

class ChatConversationController extends ChangeNotifier {
  ChatConversationController({
    required this.chatFacade,
    required this.currentUserId,
    required this.conversation,
  });

  final ChatFacade chatFacade;
  final int currentUserId;
  final Conversation conversation;

  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  ConversationTrustState? _trust;
  Timer? _pollingTimer;
  List<AttachmentTransferState> _attachmentTransfers = const [];
  StreamSubscription<ChatRealtimeEvent>? _realtimeSubscription;
  bool _peerOnline = false;
  DateTime? _peerLastSeenAt;
  final Set<int> _typingUserIds = <int>{};

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  ConversationTrustState? get trust => _trust;
  List<AttachmentTransferState> get attachmentTransfers => _attachmentTransfers
      .where((item) => item.conversationId == conversation.id)
      .toList();
  bool get peerOnline => _peerOnline;
  DateTime? get peerLastSeenAt => _peerLastSeenAt;
  bool get isPeerTyping => _typingUserIds.isNotEmpty;

  Future<void> initialize() async {
    _realtimeSubscription = chatFacade.realtimeEvents.listen(
      _handleRealtimeEvent,
    );
    chatFacade.attachmentTransfers?.addListener(_handleTransferUpdates);
    try {
      _attachmentTransfers = await chatFacade.loadAttachmentTransfers();
    } catch (_) {
      // Transfer history is auxiliary state. A stale/corrupt transfer cache
      // must not block conversation history from loading.
      _attachmentTransfers = const [];
    }
    await refresh();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // Polling is best-effort. A transient network/API failure must not
      // become an unhandled async exception that restarts the screen or
      // clears an already loaded conversation history.
      unawaited(
        refresh(showLoader: false).catchError((_) {
          // `refresh` stores the error on the controller; keep the current
          // message list visible until the next successful poll.
        }),
      );
    });
  }

  Future<void> refresh({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final state = await chatFacade.loadConversationMessages(
        conversation: conversation,
        currentUserId: currentUserId,
      );
      _messages = state.messages;
      _trust = state.trust;
      _error = null;
      for (final message in _messages) {
        if (message.senderId == currentUserId || message.id <= 0) continue;
        chatFacade.sendRealtimeEvent('receipt.delivered', {
          'conversation_id': conversation.id,
          'message_id': message.id,
        });
      }
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      if (showLoader) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> sendMessage(SendMessageCommand command) async {
    _isSending = true;
    notifyListeners();
    try {
      await chatFacade.sendMessage(command);
      await refresh(showLoader: false);
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> retryMessage(String clientMessageId) async {
    await chatFacade.retryMessage(
      conversation: conversation,
      currentUserId: currentUserId,
      clientMessageId: clientMessageId,
    );
    await refresh(showLoader: false);
  }

  Future<void> editMessage(int messageId, String body) async {
    await chatFacade.editMessage(messageId, body);
    await refresh(showLoader: false);
  }

  Future<void> deleteMessage(int messageId) async {
    await chatFacade.deleteMessage(messageId);
    await refresh(showLoader: false);
  }

  Future<void> forwardMessage(int messageId, int conversationId) {
    return chatFacade.forwardMessage(messageId, conversationId);
  }

  Future<void> setReaction(int messageId, String emoji) async {
    await chatFacade.setReaction(messageId, emoji);
    await refresh(showLoader: false);
  }

  Future<void> removeReaction(int messageId) async {
    await chatFacade.removeReaction(messageId);
    await refresh(showLoader: false);
  }

  Future<void> verifyCurrentKey() async {
    await chatFacade.verifyConversationPeerKey(
      currentUserId: currentUserId,
      conversation: conversation,
    );
    _trust = await chatFacade.loadConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
    );
    notifyListeners();
  }

  Future<String> downloadAttachment(ChatAttachment attachment) {
    return chatFacade.downloadAttachment(
      currentUserId: currentUserId,
      conversation: conversation,
      attachment: attachment,
    );
  }

  Future<void> pauseTransfer(String localId) async {
    await chatFacade.pauseAttachmentTransfer(localId);
  }

  Future<void> resumeTransfer(String localId) async {
    final transfer = await chatFacade.resumeAttachmentTransfer(localId);
    if (transfer?.direction == AttachmentTransferDirection.upload) {
      await refresh(showLoader: false);
    }
  }

  Future<void> cancelTransfer(String localId) async {
    await chatFacade.cancelAttachmentTransfer(localId);
  }

  Future<void> clearCompletedTransfer(String localId) async {
    await chatFacade.clearCompletedAttachmentTransfer(localId);
  }

  AttachmentTransferState? findDownloadTransfer(int attachmentId) {
    for (final transfer in _attachmentTransfers) {
      if (transfer.direction == AttachmentTransferDirection.download &&
          transfer.attachmentId == attachmentId) {
        return transfer;
      }
    }
    return null;
  }

  void _handleTransferUpdates() {
    _attachmentTransfers = chatFacade.attachmentTransfers?.value ?? const [];
    notifyListeners();
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    final payload = event.payload;
    if (event.event == 'presence.changed') {
      final userId = payload['user_id'] as int?;
      if (userId == null ||
          conversation.participantIds.contains(userId) == false) {
        return;
      }
      _peerOnline = payload['state'] == 'online';
      final rawLastSeen = payload['last_seen_at'] as String?;
      _peerLastSeenAt = rawLastSeen == null
          ? _peerLastSeenAt
          : DateTime.tryParse(rawLastSeen);
      notifyListeners();
      return;
    }
    final conversationId = payload['conversation_id'] as int?;
    if (conversationId != conversation.id) return;
    final userId = payload['user_id'] as int?;
    if (userId == null || userId == currentUserId) return;
    if (event.event == 'typing.started') {
      _typingUserIds.add(userId);
    } else if (event.event == 'typing.stopped') {
      _typingUserIds.remove(userId);
    } else {
      return;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    chatFacade.attachmentTransfers?.removeListener(_handleTransferUpdates);
    _realtimeSubscription?.cancel();
    _pollingTimer?.cancel();
    super.dispose();
  }
}
