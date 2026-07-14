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
import '../application/chat_models.dart';

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

  Future<AttachmentTransferRemoteSession> createAttachmentSession(
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
    final decoded = await apiClient
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
        })
        .then((value) {
          if (value is Map<String, dynamic>) {
            return value;
          }
          throw ApiException(
            'Attachment session response is not a JSON object.',
            code: 'attachment_session_response_invalid',
          );
        });
    return AttachmentTransferRemoteSession.fromJson(decoded);
  }

  Future<void> reportCryptoMetric(String metric) async {
    await apiClient.post('/users/me/crypto-observability', {'metric': metric});
  }

  Future<AttachmentTransferRemoteSession> getAttachmentSession(
    String sessionId,
  ) async {
    final decoded = await apiClient.get('/attachment-sessions/$sessionId');
    if (decoded is! Map<String, dynamic>) {
      throw ApiException(
        'Attachment session status response is not a JSON object.',
        code: 'attachment_session_response_invalid',
      );
    }
    return AttachmentTransferRemoteSession.fromJson(decoded);
  }

  Future<void> uploadAttachmentChunk(
    String sessionId, {
    required int chunkIndex,
    required List<int> bytes,
    required String ciphertextSha256,
  }) async {
    await apiClient.putBytes(
      '/attachment-sessions/$sessionId/chunks/$chunkIndex',
      bytes: bytes,
      headers: {
        'X-Chunk-Sha256': ciphertextSha256,
        'X-Chunk-Size': '${bytes.length}',
      },
    );
  }

  Future<ChatAttachment> completeAttachmentSession(
    String sessionId, {
    required String manifestSha256,
  }) async {
    final decoded = await apiClient.post(
      '/attachment-sessions/$sessionId/complete',
      {'manifest_sha256': manifestSha256},
    );
    if (decoded is! Map<String, dynamic> || decoded['id'] is! int) {
      throw ApiException(
        'Attachment completion response is not valid JSON.',
        code: 'attachment_completion_response_invalid',
      );
    }
    return ChatAttachment.fromJson(decoded);
  }

  Future<ChatAttachment> fetchAttachmentDownloadDescriptor(
    int attachmentId,
  ) async {
    final decoded =
        await apiClient.get('/attachments/$attachmentId/download')
            as Map<String, dynamic>;
    return ChatAttachment.fromJson(decoded);
  }

  Future<List<int>> downloadAttachmentChunk(
    int attachmentId, {
    required int chunkIndex,
  }) async {
    final response = await apiClient.getBytes(
      '/attachments/$attachmentId/chunks/$chunkIndex',
    );
    return response.bytes;
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
