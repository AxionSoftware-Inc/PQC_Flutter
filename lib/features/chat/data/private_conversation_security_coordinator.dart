import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../security/key_verification_service.dart';

class PrivateConversationSecurityCoordinator {
  const PrivateConversationSecurityCoordinator({
    required this.keyVerificationService,
  });

  final KeyVerificationService keyVerificationService;

  Future<void> prepareForSend({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required void Function(AppUser user) onUserUpdated,
  }) async {
    final _ = onUserUpdated;
    if (conversation.isGroup) {
      return;
    }

    await _guardPrivateConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
  }

  Future<void> _guardPrivateConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    if (trust.hasEnterpriseKeyChanged) {
      throw ChatEncryptionException(
        '${trust.peerUser?.displayName ?? 'Peer'} key changed. Verify the new key before sending more private messages.',
      );
    }
  }
}
