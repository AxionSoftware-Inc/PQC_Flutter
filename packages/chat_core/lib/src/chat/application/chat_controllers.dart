// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import '../../security/key_verification_service.dart';
import 'chat_facade.dart';
import 'chat_models.dart';

class ChatListController extends ChangeNotifier {
  ChatListController({
    required this.chatFacade,
    required this.currentUserId,
  });

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

  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  ConversationTrustState? get trust => _trust;

  Future<void> initialize() async {
    await refresh();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(refresh(showLoader: false));
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

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
