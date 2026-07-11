import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../security/key_verification_service.dart';

class PendingAttachmentUpload {
  const PendingAttachmentUpload({
    required this.filename,
    required this.bytes,
    required this.mimeType,
  });

  final String filename;
  final List<int> bytes;
  final String mimeType;
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
