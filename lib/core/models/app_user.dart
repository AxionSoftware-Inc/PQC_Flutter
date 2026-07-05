import 'dart:convert';

class AppUserDevice {
  const AppUserDevice({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.identityPublicKey,
    required this.keyAlgorithm,
    required this.preKeys,
  });

  final String deviceId;
  final String deviceName;
  final String platform;
  final String identityPublicKey;
  final String keyAlgorithm;
  final List<AppUserPreKey> preKeys;

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
      preKeys: (json['prekeys'] as List<dynamic>? ?? const [])
          .map((item) => AppUserPreKey.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }

  AppUserDevice copyWith({
    String? deviceId,
    String? deviceName,
    String? platform,
    String? identityPublicKey,
    String? keyAlgorithm,
    List<AppUserPreKey>? preKeys,
  }) {
    return AppUserDevice(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      keyAlgorithm: keyAlgorithm ?? this.keyAlgorithm,
      preKeys: preKeys ?? this.preKeys,
    );
  }
}

class AppUserPreKey {
  const AppUserPreKey({required this.keyId, required this.publicKey});

  final String keyId;
  final String publicKey;

  bool get hasUsablePublicKey {
    try {
      return base64Decode(publicKey).length == 32;
    } catch (_) {
      return false;
    }
  }

  factory AppUserPreKey.fromJson(Map<String, dynamic> json) {
    return AppUserPreKey(
      keyId: json['key_id'] as String? ?? '',
      publicKey: json['public_key'] as String? ?? '',
    );
  }
}

class ClaimedAppUserPreKey {
  const ClaimedAppUserPreKey({
    required this.deviceId,
    required this.keyId,
    required this.publicKey,
  });

  final String deviceId;
  final String keyId;
  final String publicKey;

  factory ClaimedAppUserPreKey.fromJson(Map<String, dynamic> json) {
    return ClaimedAppUserPreKey(
      deviceId: json['device_id'] as String,
      keyId: json['key_id'] as String,
      publicKey: json['public_key'] as String,
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

  List<AppUserDevice> get usableX25519Devices =>
      devices.where((device) => device.hasUsableX25519Key).toList();

  AppUserDevice? get preferredX25519Device {
    for (final device in usableX25519Devices) {
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

  AppUser copyWith({
    int? id,
    String? username,
    String? displayName,
    List<AppUserDevice>? devices,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      devices: devices ?? this.devices,
    );
  }
}
