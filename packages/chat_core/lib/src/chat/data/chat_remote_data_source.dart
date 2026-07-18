// ignore_for_file: implementation_imports

import 'package:crypto_core/src/crypto/group_key_store.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/attachment.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'package:crypto_core/src/models/conversation_key_envelope.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/network/api_client.dart';

class ChatRemoteDataSource implements ConversationKeyEnvelopeGateway {
  ChatRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  CryptoProtocolCapabilities? _cachedProtocolCapabilities;
  DateTime? _protocolCapabilitiesCachedAt;

  Future<CryptoProtocolCapabilities> fetchCryptoProtocolCapabilities() async {
    final cached = _cachedProtocolCapabilities;
    final cachedAt = _protocolCapabilitiesCachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(seconds: 20)) {
      return cached;
    }
    final response = await apiClient.get('/crypto/protocols');
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Server crypto protocol capability response is invalid.',
        code: 'crypto_protocol_capabilities_invalid',
        isRetryable: false,
      );
    }
    final capabilities = CryptoProtocolCapabilities.fromJson(response);
    _cachedProtocolCapabilities = capabilities;
    _protocolCapabilitiesCachedAt = DateTime.now();
    return capabilities;
  }

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
    List<int>? bytes,
    String? filePath,
    String mimeType = 'application/octet-stream',
  }) async {
    final file = filePath != null && filePath.trim().isNotEmpty
        ? await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: filename,
            contentType: _parseMediaType(mimeType),
          )
        : http.MultipartFile.fromBytes(
            'file',
            bytes ?? const [],
            filename: filename,
            contentType: _parseMediaType(mimeType),
          );
    final decoded = await apiClient.multipartPost(
      '/conversations/$conversationId/attachments',
      files: [file],
    );
    return ChatAttachment.fromJson(_extractAttachmentPayload(decoded));
  }

  Future<List<int>> downloadAttachmentFile(int attachmentId) async {
    final response = await apiClient.getBytes(
      '/attachments/$attachmentId/file',
    );
    return response.bytes;
  }

  MediaType? _parseMediaType(String mimeType) {
    try {
      return MediaType.parse(mimeType);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _extractAttachmentPayload(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded['id'] is int) {
        return decoded;
      }
      for (final key in const ['attachment', 'data', 'result']) {
        final nested = decoded[key];
        if (nested is Map<String, dynamic> && nested['id'] is int) {
          return nested;
        }
      }
    }
    throw ApiException(
      'Attachment upload succeeded but response format was not recognized.',
      code: 'attachment_response_invalid',
    );
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

class CryptoProtocolCapabilities {
  const CryptoProtocolCapabilities({
    required this.privateMessagePrefixes,
    required this.groupMessagePrefixes,
    required this.attachmentCipherVersions,
  });

  final List<String> privateMessagePrefixes;
  final List<String> groupMessagePrefixes;
  final List<String> attachmentCipherVersions;

  factory CryptoProtocolCapabilities.fromJson(Map<String, dynamic> json) {
    List<String> read(String name) => (json[name] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return CryptoProtocolCapabilities(
      privateMessagePrefixes: read('private_message_prefixes'),
      groupMessagePrefixes: read('group_message_prefixes'),
      attachmentCipherVersions: read('attachment_cipher_versions'),
    );
  }
}
