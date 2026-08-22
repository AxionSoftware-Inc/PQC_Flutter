import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:crypto_core/crypto_core.dart';
import '../../transfer/attachment_transfer.dart';
import 'chat_facade.dart';
import 'chat_models.dart';
import '../data/chat_realtime_service.dart';

/// Merges locally queued and server-confirmed messages without allowing the
/// same client message to occupy two timeline rows while a poll/realtime event
/// races the send response.
import 'chat_list_controller.dart';

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
  bool _isLoadingOlder = false;
  bool _hasOlderMessages = true;
  int _queuedSendCount = 0;
  Future<void> _sendTail = Future.value();
  String? _error;
  ConversationTrustState? _trust;
  Timer? _pollingTimer;
  bool _refreshInFlight = false;
  List<AttachmentTransferState> _attachmentTransfers = const [];
  StreamSubscription<ChatRealtimeEvent>? _realtimeSubscription;
  bool _peerOnline = false;
  DateTime? _peerLastSeenAt;
  final Set<int> _typingUserIds = <int>{};

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _queuedSendCount > 0;
  bool get isLoadingOlder => _isLoadingOlder;
  bool get hasOlderMessages => _hasOlderMessages;
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
    // Persist the conversation before reading or queueing the first message.
    // This makes restart recovery independent of whether the first network
    // request completed before the process was interrupted.
    await chatFacade.ensureConversationCached(conversation);
    try {
      _attachmentTransfers = await chatFacade.loadAttachmentTransfers();
    } catch (_) {
      // Transfer history is auxiliary state. A stale/corrupt transfer cache
      // must not block conversation history from loading.
      _attachmentTransfers = const [];
    }
    try {
      final cached = await chatFacade.readCachedConversationMessages(
        conversation.id,
      );
      if (cached.isNotEmpty) {
        _messages = cached;
        _hasOlderMessages = cached.length >= 50;
        _isLoading = false;
        notifyListeners();
      }
    } catch (_) {
      // Local cache is an optimization; authoritative sync still runs.
    }
    await refresh(showLoader: _messages.isEmpty);
    // Preload the protocol capability handshake while the user reads the
    // conversation so the first send does not pay that network round trip.
    unawaited(
      chatFacade
          .warmSendPipeline(
            conversation: conversation,
            currentUserId: currentUserId,
          )
          .catchError((_) {}),
    );
    // Realtime is the primary delivery path. Keep a modest polling fallback
    // for reconnect recovery without continuously competing with encryption
    // and send requests on slower mobile networks.
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
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
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    if (showLoader) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      final state = await chatFacade.loadConversationMessages(
        conversation: conversation,
        currentUserId: currentUserId,
      );
      // Polling only returns the newest window. Replacing an expanded local
      // timeline with that window makes older rows disappear every few
      // seconds, which in turn resets scroll position and replays decrypt
      // placeholders. Keep older pages already loaded by the user and let
      // fresh server rows replace only their matching ids.
      _messages = mergeChatTimeline(_messages, state.messages);
      _hasOlderMessages = _messages.length >= 50;
      _trust = state.trust;
      _error = null;
      for (final message in _messages) {
        if (message.senderId == currentUserId || message.id <= 0) continue;
        chatFacade.sendRealtimeEvent('receipt.delivered', {
          'conversation_id': conversation.id,
          'message_id': message.id,
        });
      }
      // Opening a conversation is the read action. Persist it through the
      // HTTP fallback as well, so the sender's second check is not dependent
      // on websocket availability.
      markMessagesRead();
    } catch (error) {
      _error = error.toString();
      rethrow;
    } finally {
      _refreshInFlight = false;
      if (showLoader) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadOlderMessages() async {
    if (_isLoadingOlder || !_hasOlderMessages || _messages.isEmpty) return;
    _isLoadingOlder = true;
    notifyListeners();
    try {
      final state = await chatFacade.loadOlderConversationMessages(
        conversation: conversation,
        currentUserId: currentUserId,
      );
      if (state.messages.length == _messages.length) {
        _hasOlderMessages = false;
      }
      _messages = state.messages;
    } finally {
      _isLoadingOlder = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(SendMessageCommand command) {
    final prepared = command.copyWith(
      clientMessageId:
          command.clientMessageId ??
          '${command.conversation.id}_${command.currentUserId}_${DateTime.now().toUtc().microsecondsSinceEpoch}',
    );
    _queuedSendCount++;
    notifyListeners();
    final operation = _sendTail.then((_) => _sendMessageInOrder(prepared));
    // A failed message remains in the durable outbox, but it must not block
    // the next message the user already queued in the composer.
    _sendTail = operation.catchError((_) {});
    return operation.whenComplete(() {
      _queuedSendCount--;
      notifyListeners();
    });
  }

  Future<void> _sendMessageInOrder(SendMessageCommand command) async {
    try {
      final sent = await chatFacade.sendMessage(command);
      // The send pipeline already persists this acknowledged message locally.
      // Render it immediately instead of waiting for another decrypt/poll cycle.
      _messages = mergeChatTimeline(_messages, [sent]);
      notifyListeners();
      // Reconcile receipts/realtime state later without delaying the composer.
      unawaited(refresh(showLoader: false).catchError((_) {}));
    } catch (error) {
      _messages = _messages
          .map((message) {
            if (message.clientMessageId != command.clientMessageId) {
              return message;
            }
            return message.copyWith(
              deliveryState: MessageDeliveryState.failedRetryable,
              failureReason: error.toString(),
            );
          })
          .toList(growable: false);
      notifyListeners();
      rethrow;
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

  void markMessagesRead() {
    for (final message in _messages) {
      if (message.id <= 0 || message.senderId == currentUserId) continue;
      chatFacade.sendRealtimeEvent('receipt.read', {
        'conversation_id': conversation.id,
        'message_id': message.id,
      });
      // HTTP is the durable fallback when the websocket is reconnecting or
      // the server's channel layer cannot broadcast across workers.
      unawaited(chatFacade.markMessageRead(message.id).catchError((_) {}));
    }
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
    final transfer = await chatFacade.resumeAttachmentTransfer(
      localId: localId,
      conversation: conversation,
      currentUserId: currentUserId,
    );
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
    if (event.event == 'receipt.read' || event.event == 'receipt.delivered') {
      final messageId = payload['message_id'] as int?;
      if (messageId == null) return;
      var changed = false;
      _messages = _messages.map((message) {
        if (message.id != messageId || message.senderId != currentUserId) {
          return message;
        }
        final isRead = event.event == 'receipt.read' || message.isRead;
        if (message.isRead == isRead) return message;
        changed = true;
        return message.copyWith(isRead: isRead);
      }).toList();
      if (changed) notifyListeners();
      return;
    }
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
