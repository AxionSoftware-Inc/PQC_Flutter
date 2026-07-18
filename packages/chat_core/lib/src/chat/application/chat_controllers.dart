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
      // A background poll can fail while the server closes a keep-alive
      // connection. Do not cover an already loaded chat with a scary error
      // banner; the next poll will reconcile it. Initial-load failures still
      // remain visible to the user.
      if (_users.isEmpty && _conversations.isEmpty) {
        _error = error.toString();
      }
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

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  ConversationTrustState? get trust => _trust;
  List<AttachmentTransferState> get attachmentTransfers => _attachmentTransfers
      .where((item) => item.conversationId == conversation.id)
      .toList();

  Future<void> initialize() async {
    chatFacade.attachmentTransfers?.addListener(_handleTransferUpdates);
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
        _isLoading = false;
        notifyListeners();
      }
    } catch (_) {
      // Cache is an optimization; authoritative sync still runs.
    }
    await refresh(showLoader: _messages.isEmpty);
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
    } catch (error) {
      // A background poll can fail while the server closes a keep-alive
      // connection. Do not cover an already loaded chat with a scary error
      // banner; the next poll will reconcile it. Initial-load failures still
      // remain visible to the user.
      if (_messages.isEmpty) {
        _error = error.toString();
      }
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
      final sent = await chatFacade.sendMessage(command);
      // The send response already contains the authoritative message. Keeping
      // it locally avoids making the composer wait for a second full history
      // request before it becomes available again.
      _messages = [
        ..._messages.where(
          (item) =>
              item.id != sent.id &&
              item.clientMessageId != sent.clientMessageId,
        ),
        sent,
      ]..sort((left, right) => left.createdAt.compareTo(right.createdAt));
      _error = null;
      notifyListeners();
      // Reconcile in the background for events created on other devices.
      unawaited(refresh(showLoader: false).catchError((_) {}));
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

  @override
  void dispose() {
    chatFacade.attachmentTransfers?.removeListener(_handleTransferUpdates);
    _pollingTimer?.cancel();
    super.dispose();
  }
}
