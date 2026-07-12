import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'chat_models.dart';

class ConversationDevicePolicy {
  const ConversationDevicePolicy();

  AppUser? resolvePeerUser({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    if (conversation.isGroup) {
      return null;
    }
    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    if (peerUserId < 0) {
      return null;
    }
    return usersById[peerUserId];
  }

  DeviceResolutionResult resolvePrivatePeerPqcDevice({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final peerUser = resolvePeerUser(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    if (peerUser == null) {
      return const DeviceResolutionResult(
        issue: DeviceResolutionIssue.missingPeerUser,
      );
    }
    final device = peerUser.preferredPqcDevice;
    if (device == null) {
      return DeviceResolutionResult(
        peerUser: peerUser,
        issue: DeviceResolutionIssue.peerNotPqcReady,
      );
    }
    return DeviceResolutionResult(peerUser: peerUser, device: device);
  }

  AppUserDevice? findDeviceById({
    required Map<int, AppUser> usersById,
    required String deviceId,
    int? excludeUserId,
  }) {
    for (final user in usersById.values) {
      if (excludeUserId != null && user.id == excludeUserId) {
        continue;
      }
      for (final device in user.devices) {
        if (device.deviceId == deviceId) {
          return device;
        }
      }
    }
    return null;
  }

  GroupDeviceResolutionResult resolveGroupTargetDevices({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final targetDevices = <AppUserDevice>[];
    final missingParticipants = <String>[];

    for (final userId in conversation.participantIds) {
      final user = usersById[userId];
      if (user == null) {
        missingParticipants.add('user-$userId');
        continue;
      }

      final usableDevices = user.devices
          .where((device) => device.hasUsableMlKemKey && device.hasUsableMlDsaKey)
          .toList();
      if (usableDevices.isEmpty) {
        missingParticipants.add(user.displayName);
        continue;
      }
      targetDevices.addAll(usableDevices);
    }

    if (missingParticipants.isNotEmpty) {
      return GroupDeviceResolutionResult(
        devices: targetDevices,
        issue: DeviceResolutionIssue.missingParticipants,
        missingParticipants: missingParticipants,
      );
    }
    if (targetDevices.isEmpty) {
      return const GroupDeviceResolutionResult(
        devices: [],
        issue: DeviceResolutionIssue.noUsableTargetDevices,
      );
    }
    return GroupDeviceResolutionResult(devices: targetDevices);
  }

  String buildParticipantSignature({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final entries = <String>[];
    final participantIds = [...conversation.participantIds]..sort();
    for (final userId in participantIds) {
      final user = usersById[userId];
      if (user == null) {
        entries.add('$userId:missing');
        continue;
      }
      final devices = user.devices
          .where((item) => item.hasUsableMlKemKey && item.hasUsableMlDsaKey)
          .map(
            (item) =>
                '${item.deviceId}:${item.pqcPublicKey}:${item.pqcSigningPublicKey}',
          )
          .toList()
        ..sort();
      if (devices.isEmpty) {
        entries.add('$userId:none');
        continue;
      }
      entries.add('$userId:${devices.join("|")}');
    }
    return entries.join('||');
  }
}
