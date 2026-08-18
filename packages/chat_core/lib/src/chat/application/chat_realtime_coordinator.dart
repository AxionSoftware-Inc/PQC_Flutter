part of 'chat_services.dart';

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
      senderId: event.payload['sender_id'] as int?,
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
    int? senderId,
    required Future<void> Function() refreshUsers,
  }) async {
    final plaintext = await cryptoService.decrypt(
      request: ChatCryptoRequest(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
        senderId: senderId,
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
        senderId: senderId,
      ),
      payload: payload,
    );
  }
}
