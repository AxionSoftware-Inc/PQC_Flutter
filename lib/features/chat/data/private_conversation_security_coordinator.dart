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
    await _guardConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
  }

  Future<void> _guardConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    if (conversation.isGroup) {
      return;
    }
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    if (!trust.isAvailable || !trust.isEnterpriseReady) {
      throw ChatEncryptionException(
        '${trust.peerUser?.displayName ?? 'Peer'} PQC security material is not ready yet. Verify both devices are fully synced before sending private messages.',
      );
    }
    if (trust.hasEnterpriseKeyChanged) {
      throw ChatEncryptionException(
        '${trust.peerUser?.displayName ?? 'Peer'} key changed. Verify the new key before sending more private messages.',
      );
    }
    if (!trust.isEnterpriseVerified) {
      final peerUser = trust.peerUser;
      if (peerUser == null) {
        throw ChatEncryptionException(
          'Peer security material could not be resolved.',
        );
      }
      await keyVerificationService.verifyUser(peerUser);
    }
  }
}
