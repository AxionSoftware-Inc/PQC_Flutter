import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';

class ChatCryptoContext {
  const ChatCryptoContext({
    required this.currentUserId,
    required this.conversation,
    required this.usersById,
    this.messageId = '',
    this.senderId,
  });

  final int currentUserId;
  final Conversation conversation;
  final Map<int, AppUser> usersById;
  final String messageId;

  /// Server-authenticated sender for incoming payloads.  It is intentionally
  /// optional because conversation previews do not currently carry it.
  final int? senderId;
}
