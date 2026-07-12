import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';

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
