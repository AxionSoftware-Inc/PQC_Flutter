import 'dart:convert';

class AppUserDevice {
  const AppUserDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.identityPublicKey,
    required this.keyAlgorithm,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String identityPublicKey;
  final String keyAlgorithm;

  bool get hasUsableX25519Key =>
      keyAlgorithm == 'x25519' && _hasValidX25519PublicKey(identityPublicKey);

  static bool _hasValidX25519PublicKey(String value) {
    if (value.isEmpty) {
      return false;
    }

    try {
      return base64Decode(value).length == 32;
    } catch (_) {
      return false;
    }
  }

  factory AppUserDevice.fromJson(Map<String, dynamic> json) {
    return AppUserDevice(
      deviceId: json['device_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      keyAlgorithm: json['key_algorithm'] as String? ?? '',
    );
  }
}

class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.devices,
  });

  final int id;
  final String username;
  final String displayName;
  final List<AppUserDevice> devices;

  bool get hasUsableDeviceKey => preferredX25519Device != null;

  AppUserDevice? get preferredX25519Device {
    for (final device in devices) {
      if (device.hasUsableX25519Key) {
        return device;
      }
    }
    return null;
  }

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as int,
      username: json['username'] as String,
      displayName:
          (json['display_name'] as String?) ?? json['username'] as String,
      devices: (json['devices'] as List<dynamic>? ?? const [])
          .map((item) => AppUserDevice.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
