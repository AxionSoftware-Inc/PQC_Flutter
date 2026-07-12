// ignore_for_file: implementation_imports

import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/chat_message.dart';
import 'package:crypto_core/src/models/conversation.dart';
import '../../security/key_verification_service.dart';

class PendingAttachmentUpload {
  const PendingAttachmentUpload({
    required this.filename,
    required this.mimeType,
    this.bytes,
    this.filePath,
    this.sizeBytes = 0,
  });

  final String filename;
  final List<int>? bytes;
  final String? filePath;
  final String mimeType;
  final int sizeBytes;

  bool get hasUploadSource =>
      (bytes != null && bytes!.isNotEmpty) ||
      (filePath != null && filePath!.trim().isNotEmpty);

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'bytes': bytes,
      'file_path': filePath,
      'mime_type': mimeType,
      'size_bytes': sizeBytes,
    };
  }

  factory PendingAttachmentUpload.fromJson(Map<String, dynamic> json) {
    return PendingAttachmentUpload(
      filename: json['filename'] as String? ?? '',
      bytes: (json['bytes'] as List<dynamic>?)?.whereType<int>().toList(),
      filePath: json['file_path'] as String?,
      mimeType: json['mime_type'] as String? ?? 'application/octet-stream',
      sizeBytes: json['size_bytes'] as int? ?? 0,
    );
  }
}

class AttachmentTransferRemoteSession {
  const AttachmentTransferRemoteSession({
    required this.sessionId,
    required this.filename,
    required this.mimeType,
    required this.cipherVersion,
    required this.plaintextSize,
    required this.ciphertextSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.plaintextSha256,
    required this.manifestSha256,
    required this.fileKeyWrap,
    required this.status,
    required this.receivedChunks,
    this.completedAttachmentId,
  });

  final String sessionId;
  final String filename;
  final String mimeType;
  final String cipherVersion;
  final int plaintextSize;
  final int ciphertextSize;
  final int chunkSize;
  final int totalChunks;
  final String plaintextSha256;
  final String manifestSha256;
  final String fileKeyWrap;
  final String status;
  final List<int> receivedChunks;
  final int? completedAttachmentId;

  factory AttachmentTransferRemoteSession.fromJson(Map<String, dynamic> json) {
    return AttachmentTransferRemoteSession(
      sessionId: json['session_id'] as String? ?? '',
      filename: json['filename'] as String? ?? '',
      mimeType: json['mime_type'] as String? ?? '',
      cipherVersion: json['cipher_version'] as String? ?? 'attachment:v1',
      plaintextSize: json['plaintext_size'] as int? ?? 0,
      ciphertextSize: json['ciphertext_size'] as int? ?? 0,
      chunkSize: json['chunk_size'] as int? ?? 0,
      totalChunks: json['total_chunks'] as int? ?? 0,
      plaintextSha256: json['plaintext_sha256'] as String? ?? '',
      manifestSha256: json['manifest_sha256'] as String? ?? '',
      fileKeyWrap: json['file_key_wrap'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      receivedChunks: (json['received_chunks'] as List<dynamic>? ?? const [])
          .whereType<int>()
          .toList(),
      completedAttachmentId: json['completed_attachment'] as int?,
    );
  }
}

class SendMessageCommand {
  const SendMessageCommand({
    required this.conversation,
    required this.currentUserId,
    required this.text,
    this.messageType = 'text',
    this.attachments = const [],
  });

  final Conversation conversation;
  final int currentUserId;
  final String text;
  final String messageType;
  final List<PendingAttachmentUpload> attachments;
}

class ChatListState {
  const ChatListState({
    required this.users,
    required this.conversations,
    required this.trustByUserId,
  });

  final List<AppUser> users;
  final List<Conversation> conversations;
  final Map<int, UserKeyTrust> trustByUserId;
}

class ConversationTrustState {
  const ConversationTrustState({required this.trust});

  final ConversationKeyTrust trust;
}

class ChatConversationState {
  const ChatConversationState({
    required this.messages,
    this.trust,
  });

  final List<ChatMessage> messages;
  final ConversationTrustState? trust;
}

enum DeviceResolutionIssue {
  missingPeerUser,
  peerNotPqcReady,
  missingParticipants,
  noUsableTargetDevices,
}

class DeviceResolutionResult {
  const DeviceResolutionResult({
    this.peerUser,
    this.device,
    this.issue,
    this.missingParticipants = const [],
  });

  final AppUser? peerUser;
  final AppUserDevice? device;
  final DeviceResolutionIssue? issue;
  final List<String> missingParticipants;

  bool get isReady => device != null && issue == null;
}

class GroupDeviceResolutionResult {
  const GroupDeviceResolutionResult({
    required this.devices,
    this.issue,
    this.missingParticipants = const [],
  });

  final List<AppUserDevice> devices;
  final DeviceResolutionIssue? issue;
  final List<String> missingParticipants;

  bool get isReady => devices.isNotEmpty && issue == null;
}
