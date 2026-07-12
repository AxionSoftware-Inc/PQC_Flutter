import 'package:crypto_core/src/models/app_user.dart';

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
