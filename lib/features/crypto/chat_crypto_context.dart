import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';

class ChatCryptoContext {
  const ChatCryptoContext({
    required this.currentUserId,
    required this.conversation,
    required this.usersById,
  });

  final int currentUserId;
  final Conversation conversation;
  final Map<int, AppUser> usersById;
}
