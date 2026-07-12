// ignore_for_file: implementation_imports

import 'package:crypto_core/src/crypto/group_key_store.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'package:crypto_core/src/models/conversation_key_envelope.dart';
import '../../core/network/api_client.dart';
import 'package:http/http.dart' as http;

class ChatRemoteDataSource implements ConversationKeyEnvelopeGateway {
  ChatRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  Future<List<AppUser>> fetchUsers() async {
    final response = await apiClient.get('/users') as List<dynamic>;
    return response
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
        .toList();
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
    String messageType = 'text',
    List<int> attachmentIds = const [],
  }) async {
    final response =
        await apiClient.post('/conversations/$conversationId/messages', {
              'body': body,
              'client_message_id': clientMessageId,
              'message_type': messageType,
              'attachment_ids': attachmentIds,
            })
            as Map<String, dynamic>;
    return ChatMessage.fromJson(response);
  }

  Future<ChatAttachment> uploadAttachment(
    int conversationId, {
    required String filename,
    required List<int> bytes,
    String mimeType = 'application/octet-stream',
  }) async {
    final decoded =
        await apiClient.multipartPost(
              '/conversations/$conversationId/attachments',
              files: [
                http.MultipartFile.fromBytes('file', bytes, filename: filename),
              ],
            )
            as Map<String, dynamic>;
    return ChatAttachment.fromJson(decoded);
  }

  @override
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

  @override
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
