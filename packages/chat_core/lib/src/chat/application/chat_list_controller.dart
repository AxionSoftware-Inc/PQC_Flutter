import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:crypto_core/crypto_core.dart';
import '../../security/key_verification_service.dart';
import 'chat_facade.dart';

/// Merges locally queued and server-confirmed messages without allowing the
/// same client message to occupy two timeline rows while a poll/realtime event
/// races the send response.
List<ChatMessage> mergeChatTimeline(
  List<ChatMessage> existing,
  List<ChatMessage> incoming,
) {
  if (existing.isEmpty) {
    return incoming;
  }
  final byStableId = <String, ChatMessage>{};
  for (final message in existing) {
    byStableId[chatTimelineIdentity(message)] = message;
  }
  for (final message in incoming) {
    // Incoming state is authoritative: it replaces a matching local outbox
    // row once the server has assigned an id.
    byStableId[chatTimelineIdentity(message)] = message;
  }
  final merged = byStableId.values.toList()
    ..sort((left, right) {
      final byTime = left.createdAt.compareTo(right.createdAt);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
  return merged;
}

@visibleForTesting
String chatTimelineIdentity(ChatMessage message) {
  // client_message_id is the idempotency identity shared by the optimistic
  // outbox row and its server-confirmed counterpart. It must take precedence
  // over the server id or a periodic refresh displays the same send twice.
  if (message.clientMessageId.isNotEmpty) {
    return 'client:${message.clientMessageId}';
  }
  if (message.id > 0) return 'server:${message.id}';
  return 'transient:${message.senderId}:${message.createdAt.microsecondsSinceEpoch}';
}

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
