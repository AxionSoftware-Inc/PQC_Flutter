import '../../../core/models/app_user.dart';
import '../../../core/models/conversation.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../security/key_verification_service.dart';
import 'chat_remote_data_source.dart';

class PrivateConversationSecurityCoordinator {
  const PrivateConversationSecurityCoordinator({
    required this.remoteDataSource,
    required this.keyVerificationService,
  });

  final ChatRemoteDataSource remoteDataSource;
  final KeyVerificationService keyVerificationService;

  Future<void> prepareForSend({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required void Function(AppUser user) onUserUpdated,
  }) async {
    if (conversation.isGroup) {
      return;
    }

    await _guardPrivateConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    await _preparePeerPreKey(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
      onUserUpdated: onUserUpdated,
    );
  }

  Future<void> _preparePeerPreKey({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required void Function(AppUser user) onUserUpdated,
  }) async {
    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    final peerUser = usersById[peerUserId];
    final peerDevice = peerUser?.preferredX25519Device;
    if (peerUser == null || peerDevice == null) {
      return;
    }

    final claimedPreKey = await remoteDataSource.claimPreKey(
      userId: peerUser.id,
      deviceId: peerDevice.deviceId,
    );
    final nextPreKeys = claimedPreKey == null
        ? const <AppUserPreKey>[]
        : [
            AppUserPreKey(
              keyId: claimedPreKey.keyId,
              publicKey: claimedPreKey.publicKey,
            ),
          ];

    final updatedDevices = peerUser.devices.map((device) {
      if (device.deviceId != peerDevice.deviceId) {
        return device;
      }
      return device.copyWith(preKeys: nextPreKeys);
    }).toList();

    onUserUpdated(peerUser.copyWith(devices: updatedDevices));
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
    if (trust.hasKeyChanged) {
      throw ChatEncryptionException(
        '${trust.peerUser?.displayName ?? 'Peer'} key changed. Verify the new key before sending more private messages.',
      );
    }
  }
}
