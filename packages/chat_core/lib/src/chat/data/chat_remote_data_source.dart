import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_core/crypto_core.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../core/network/api_client.dart';

class ChatRemoteDataSource implements ConversationKeyEnvelopeGateway {
  ChatRemoteDataSource({required this.apiClient});

  final ApiClient apiClient;

  Future<CryptoProtocolCapabilities> fetchCryptoProtocolCapabilities() async {
    final response = await apiClient.get('/crypto/protocols');
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Server crypto protocol capability response is invalid.',
        code: 'crypto_protocol_capabilities_invalid',
        isRetryable: false,
      );
    }
    return CryptoProtocolCapabilities.fromJson(response);
  }

  Future<List<AppUser>> fetchUsers() async {
    final response = await apiClient.get('/users') as List<dynamic>;
    return response
        .map((item) => AppUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<AppUser> updateUserRole(int userId, String role) async {
    final response =
        await apiClient.put('/users/$userId/role', {'role': role})
            as Map<String, dynamic>;
    return AppUser.fromJson(response);
  }

  Future<List<Conversation>> fetchConversations({
    DateTime? updatedAfter,
    String search = '',
    int offset = 0,
    int limit = 50,
  }) async {
    final query = <String, String>{
      if (updatedAfter != null)
        'updated_after': updatedAfter.toUtc().toIso8601String(),
      if (search.trim().isNotEmpty) 'search': search.trim(),
      'offset': '$offset',
      'limit': '$limit',
    };
    final response =
        await apiClient.get('/conversations', queryParameters: query)
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
    int? beforeId,
    int limit = 50,
  }) async {
    final query = <String, String>{'limit': '$limit'};
    if (afterId != null) query['after_id'] = '$afterId';
    if (beforeId != null) query['before_id'] = '$beforeId';
    final response =
        await apiClient.get(
              '/conversations/$conversationId/messages',
              queryParameters: query,
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

  Future<ChatMessage> editMessage(int messageId, String body) async {
    final response = await apiClient.patch('/messages/$messageId', {
      'body': body,
    });
    return ChatMessage.fromJson(response as Map<String, dynamic>);
  }

  Future<void> deleteMessage(int messageId) async {
    await apiClient.delete('/messages/$messageId');
  }

  Future<void> markMessageRead(int messageId) async {
    await apiClient.post('/messages/$messageId/read', const {});
  }

  Future<ChatMessage> forwardMessage(int messageId, int conversationId) async {
    final response = await apiClient.post('/messages/$messageId', {
      'conversation_id': conversationId,
    });
    return ChatMessage.fromJson(response as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> setReaction(int messageId, String emoji) async {
    final response = await apiClient.post('/messages/$messageId/reaction', {
      'emoji': emoji,
    });
    return response as Map<String, dynamic>;
  }

  Future<void> removeReaction(int messageId) async {
    await apiClient.delete('/messages/$messageId/reaction');
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

  Future<Map<String, dynamic>> createAttachmentSession(
    int conversationId, {
    required String filename,
    required String mimeType,
    required String cipherVersion,
    required int plaintextSize,
    required int ciphertextSize,
    required int chunkSize,
    required int totalChunks,
    required String plaintextSha256,
    required String manifestSha256,
    required String fileKeyWrap,
    String conversationEpochId = '',
    int recoveryManifestSequence = 0,
  }) async {
    final response = await apiClient
        .post('/conversations/$conversationId/attachment-sessions', {
          'filename': filename,
          'mime_type': mimeType,
          'cipher_version': cipherVersion,
          'plaintext_size': plaintextSize,
          'ciphertext_size': ciphertextSize,
          'chunk_size': chunkSize,
          'total_chunks': totalChunks,
          'plaintext_sha256': plaintextSha256,
          'manifest_sha256': manifestSha256,
          'file_key_wrap': fileKeyWrap,
          'conversation_epoch_id': conversationEpochId,
          'recovery_manifest_sequence': recoveryManifestSequence,
        });
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Attachment session response is invalid.',
        code: 'attachment_session_response_invalid',
        isRetryable: false,
      );
    }
    return response;
  }

  Future<void> uploadAttachmentChunk({
    required String sessionId,
    required int chunkIndex,
    required List<int> ciphertext,
  }) async {
    await apiClient.putBytes(
      '/attachment-sessions/$sessionId/chunks/$chunkIndex',
      bytes: ciphertext,
      headers: {
        'X-Chunk-Size': '${ciphertext.length}',
        'X-Chunk-Sha256': _sha256Hex(ciphertext),
      },
    );
  }

  Future<ChatAttachment> completeAttachmentSession({
    required String sessionId,
    required String manifestSha256,
  }) async {
    final response = await apiClient.post(
      '/attachment-sessions/$sessionId/complete',
      {'manifest_sha256': manifestSha256},
    );
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Attachment completion response is invalid.',
        code: 'attachment_completion_response_invalid',
        isRetryable: false,
      );
    }
    return ChatAttachment.fromJson(response);
  }

  Future<ChatAttachment> fetchAttachmentDescriptor(int attachmentId) async {
    final response = await apiClient.get('/attachments/$attachmentId/download');
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Attachment descriptor response is invalid.',
        code: 'attachment_descriptor_response_invalid',
        isRetryable: false,
      );
    }
    return ChatAttachment.fromJson(response);
  }

  Future<List<int>> downloadAttachmentChunk({
    required int attachmentId,
    required int chunkIndex,
  }) async {
    final response = await apiClient.getBytes(
      '/attachments/$attachmentId/chunks/$chunkIndex',
    );
    return response.bytes;
  }

  Future<List<int>> downloadAttachmentFile(int attachmentId) async {
    final response = await apiClient.getBytes(
      '/attachments/$attachmentId/file',
    );
    return response.bytes;
  }

  String _sha256Hex(List<int> bytes) => crypto.sha256.convert(bytes).toString();

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
    this.readableAttachmentCipherVersions = const [],
    this.readableGroupEnvelopePrefixes = const [],
    this.groupEnvelopePrefixes = const [],
    this.minimumDecoderVersion = 0,
    this.activeGroupEnvelopeWriter = 'v2',
  });

  final List<String> privateMessagePrefixes;
  final List<String> groupMessagePrefixes;
  final List<String> attachmentCipherVersions;
  final List<String> readableAttachmentCipherVersions;
  final List<String> readableGroupEnvelopePrefixes;
  final List<String> groupEnvelopePrefixes;
  final int minimumDecoderVersion;
  final String activeGroupEnvelopeWriter;

  factory CryptoProtocolCapabilities.fromJson(Map<String, dynamic> json) {
    List<String> read(String name) => (json[name] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false);
    return CryptoProtocolCapabilities(
      privateMessagePrefixes: read('private_message_prefixes'),
      groupMessagePrefixes: read('group_message_prefixes'),
      attachmentCipherVersions: read('attachment_cipher_versions'),
      readableAttachmentCipherVersions: read(
        'readable_attachment_cipher_versions',
      ),
      readableGroupEnvelopePrefixes: read('readable_group_envelope_prefixes'),
      groupEnvelopePrefixes: read('group_envelope_prefixes'),
      minimumDecoderVersion:
          int.tryParse(
            json['minimum_decoder_version']?.toString().split('.').first ?? '',
          ) ??
          0,
      activeGroupEnvelopeWriter:
          json['active_group_envelope_writer'] as String? ?? 'v2',
    );
  }
}
