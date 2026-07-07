import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/network/api_client.dart';
import '../../crypto/chat_cipher_service.dart';
import '../../crypto/chat_crypto_context.dart';
import '../../security/key_verification_service.dart';
import 'chat_remote_data_source.dart';
import 'outbox_store.dart';
import 'private_conversation_security_coordinator.dart';

class ChatRepository {
  ChatRepository({
    required this.remoteDataSource,
    required this.cipherService,
    required this.keyVerificationService,
    required this.privateConversationSecurityCoordinator,
    OutboxStore? outboxStore,
  }) : outboxStore = outboxStore ?? OutboxStore();

  final ChatRemoteDataSource remoteDataSource;
  final ChatCipherService cipherService;
  final KeyVerificationService keyVerificationService;
  final PrivateConversationSecurityCoordinator
  privateConversationSecurityCoordinator;
  final OutboxStore outboxStore;
  final Map<int, AppUser> _usersById = {};
  final Map<int, Conversation> _conversationsById = {};
  final Map<int, List<ChatMessage>> _messageCacheByConversation = {};
  final Map<int, int> _lastMessageIdByConversation = {};
  DateTime? _lastConversationSyncAt;

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
    await _ensureUsersLoaded();
    final conversations = await remoteDataSource.fetchConversations(
      updatedAfter: _lastConversationSyncAt,
    );
    _lastConversationSyncAt = DateTime.now().toUtc();
    final decoded = <Conversation>[];
    for (final conversation in conversations) {
      final preview = conversation.lastMessagePreview.isEmpty
          ? ''
          : await cipherService.decrypt(
              context: _cryptoContext(
                currentUserId: currentUserId,
                conversation: conversation,
              ),
              payload: conversation.lastMessagePreview,
            );
      final merged = conversation.copyWith(
        lastMessagePreview: preview.length > 80
            ? preview.substring(0, 80)
            : preview,
      );
      _conversationsById[merged.id] = merged;
      decoded.add(merged);
    }
    final all = _conversationsById.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return all;
  }

  Future<Conversation> openPrivateConversation(int otherUserId) =>
      remoteDataSource.openPrivateConversation(otherUserId);

  Future<List<ChatMessage>> fetchMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    await _ensureUsersLoaded();
    await flushPendingMessages(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    final messages = await remoteDataSource.fetchMessages(
      conversation.id,
      afterId: _lastMessageIdByConversation[conversation.id],
    );
    final existing = [...?_messageCacheByConversation[conversation.id]];
    final decoded = <ChatMessage>[];
    for (final message in messages) {
      decoded.add(
        ChatMessage(
          id: message.id,
          conversationId: message.conversationId,
          senderId: message.senderId,
          senderName: message.senderName,
          body: await cipherService.decrypt(
            context: _cryptoContext(
              currentUserId: currentUserId,
              conversation: conversation,
            ),
            payload: message.body,
          ),
          createdAt: message.createdAt,
          clientMessageId: message.clientMessageId,
          deliveryState: message.deliveryState,
        ),
      );
    }
    if (decoded.isNotEmpty) {
      _lastMessageIdByConversation[conversation.id] = decoded.last.id;
    }
    final pending = await outboxStore.readForConversation(conversation.id);
    final mergedRemote = _mergeRemoteMessages(existing, decoded);
    _messageCacheByConversation[conversation.id] = mergedRemote;
    return _mergeMessages(mergedRemote, pending);
  }

  Future<ChatMessage> sendMessage(
    Conversation conversation, {
    required int currentUserId,
    required String text,
  }) async {
    await _ensureUsersLoaded();
    await privateConversationSecurityCoordinator.prepareForSend(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
      onUserUpdated: (user) {
        _usersById[user.id] = user;
      },
    );
    final now = DateTime.now().toUtc();
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
      );
      await outboxStore.remove(clientMessageId);
      return sent;
    } on ApiException catch (error) {
      final state = error.isRetryable
          ? MessageDeliveryState.failedRetryable
          : MessageDeliveryState.failedPermanent;
      await outboxStore.upsert(
        queued.copyWith(deliveryState: state, failureReason: error.message),
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

  Future<ChatMessage> _sendQueuedMessage(
    QueuedOutgoingMessage queued, {
    required Conversation conversation,
    required int currentUserId,
  }) async {
    final payload = await cipherService.encrypt(
      context: _cryptoContext(
        currentUserId: currentUserId,
        conversation: conversation,
      ),
      plaintext: queued.plaintext,
    );
    final message = await remoteDataSource.sendMessage(
      conversation.id,
      payload,
      clientMessageId: queued.clientMessageId,
    );
    return ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      senderName: message.senderName,
      body: await cipherService.decrypt(
        context: _cryptoContext(
          currentUserId: currentUserId,
          conversation: conversation,
        ),
        payload: message.body,
      ),
      createdAt: message.createdAt,
      clientMessageId: message.clientMessageId,
      deliveryState: MessageDeliveryState.sent,
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

  List<ChatMessage> _mergeRemoteMessages(
    List<ChatMessage> existing,
    List<ChatMessage> incoming,
  ) {
    final byId = <int, ChatMessage>{for (final item in existing) item.id: item};
    for (final item in incoming) {
      byId[item.id] = item;
    }
    final merged = byId.values.toList()
      ..sort((a, b) {
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
}
