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

  Future<ClaimedAppUserPreKey?> claimPreKey({
    required int userId,
    required String deviceId,
  }) async {
    try {
      final response =
          await apiClient.post(
                '/users/$userId/devices/$deviceId/claim-prekey',
                {},
              )
              as Map<String, dynamic>;
      return ClaimedAppUserPreKey.fromJson(response);
    } on ApiException catch (error) {
      if (error.message == 'No available prekeys for this device.') {
        return null;
      }
      rethrow;
    }
  }

  Future<List<Conversation>> fetchConversations({
    DateTime? updatedAfter,
  }) async {
    final response =
        await apiClient.get(
              '/conversations',
              queryParameters: updatedAfter == null
                  ? null
                  : {'updated_after': updatedAfter.toUtc().toIso8601String()},
            )
            as List<dynamic>;
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

  Future<List<ChatMessage>> fetchMessages(
    int conversationId, {
    int? afterId,
  }) async {
    final response =
        await apiClient.get(
              '/conversations/$conversationId/messages',
              queryParameters: afterId == null
                  ? null
                  : {'after_id': '$afterId'},
            )
            as List<dynamic>;
    return response
        .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    String clientMessageId = '',
  }) async {
    final response =
        await apiClient.post('/conversations/$conversationId/messages', {
              'body': body,
              'client_message_id': clientMessageId,
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
