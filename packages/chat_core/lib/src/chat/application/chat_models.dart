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
  const ChatConversationState({required this.messages, this.trust});

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
