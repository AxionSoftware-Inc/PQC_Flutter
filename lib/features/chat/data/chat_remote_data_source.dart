import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/models/conversation_key_envelope.dart';
import '../../../core/network/api_client.dart';

class ChatRemoteDataSource {
  ChatRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  Future<List<AppUser>> fetchUsers() async {
    final response = await apiClient.get('/users') as List<dynamic>;
    return response
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<Conversation>> fetchConversations() async {
    final response = await apiClient.get('/conversations') as List<dynamic>;
    return response
        .map((item) => Conversation.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> openPrivateConversation(int otherUserId) async {
    final response =
        await apiClient.post('/private-conversations', {
              'other_user_id': otherUserId,
            })
            as Map<String, dynamic>;
    return Conversation.fromJson(response);
  }

  Future<List<ChatMessage>> fetchMessages(int conversationId) async {
    final response =
        await apiClient.get('/conversations/$conversationId/messages')
            as List<dynamic>;
    return response
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage(int conversationId, String body) async {
    final response =
        await apiClient.post('/conversations/$conversationId/messages', {
              'body': body,
            })
            as Map<String, dynamic>;
    return ChatMessage.fromJson(response);
  }

  Future<List<ConversationKeyEnvelope>> fetchConversationKeyEnvelopes(
    int conversationId,
  ) async {
    final response =
        await apiClient.get('/conversations/$conversationId/keys')
            as List<dynamic>;
    return response
        .map(
          (item) =>
              ConversationKeyEnvelope.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  Future<void> syncConversationKeyEnvelopes({
    required int conversationId,
    required String keyId,
    required String algorithm,
    required List<ConversationKeyEnvelopeUpload> envelopes,
  }) async {
    await apiClient.post('/conversations/$conversationId/keys', {
      'key_id': keyId,
      'algorithm': algorithm,
      'envelopes': envelopes.map((item) => item.toJson()).toList(),
    });
  }
}
