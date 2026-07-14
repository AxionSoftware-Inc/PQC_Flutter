import 'dart:convert';

class AppUserDevice {
  const AppUserDevice({
    required this.deviceId,
    this.keysetId = '',
    required this.deviceName,
    required this.platform,
    required this.identityPublicKey,
    required this.keyAlgorithm,
    this.pqcPublicKey = '',
    this.pqcAlgorithm = '',
    this.pqcSigningPublicKey = '',
    this.pqcSigningAlgorithm = '',
    this.status = 'active',
    this.profileFingerprint = '',
    this.revokedReason = '',
    this.createdAt,
    this.updatedAt,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String deviceId;
  final String keysetId;
  final String deviceName;
  final String platform;
  final String identityPublicKey;
  final String keyAlgorithm;
  final String pqcPublicKey;
  final String pqcAlgorithm;
  final String pqcSigningPublicKey;
  final String pqcSigningAlgorithm;
  final String status;
  final String profileFingerprint;
  final String revokedReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  bool get isActive => status == 'active';

  bool get hasUsableX25519Key =>
      keyAlgorithm == 'x25519' && _hasValidX25519PublicKey(identityPublicKey);

  bool get hasUsableMlKemKey =>
      pqcAlgorithm == 'ml-kem-768' && _hasValidMlKemPublicKey(pqcPublicKey);

  bool get hasUsableMlDsaKey =>
      pqcSigningAlgorithm == 'ml-dsa-65' &&
      _hasValidMlDsaPublicKey(pqcSigningPublicKey);

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

  static bool _hasValidMlKemPublicKey(String value) {
    if (value.isEmpty) {
      return false;
    }

    try {
      return base64Decode(value).length == 1184;
    } catch (_) {
      return false;
    }
  }

  static bool _hasValidMlDsaPublicKey(String value) {
    if (value.isEmpty) {
      return false;
    }

    try {
      return base64Decode(value).length == 1952;
    } catch (_) {
      return false;
    }
  }

  factory AppUserDevice.fromJson(Map<String, dynamic> json) {
    return AppUserDevice(
      deviceId: json['device_id'] as String? ?? '',
      keysetId: json['keyset_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      keyAlgorithm: json['key_algorithm'] as String? ?? '',
      pqcPublicKey: json['pqc_public_key'] as String? ?? '',
      pqcAlgorithm: json['pqc_algorithm'] as String? ?? '',
      pqcSigningPublicKey: json['pqc_signing_public_key'] as String? ?? '',
      pqcSigningAlgorithm: json['pqc_signing_algorithm'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      profileFingerprint: json['profile_fingerprint'] as String? ?? '',
      revokedReason: json['revoked_reason'] as String? ?? '',
      createdAt: _parseDate(json['created_at'] as String?),
      updatedAt: _parseDate(json['updated_at'] as String?),
      firstSeenAt: _parseDate(json['first_seen_at'] as String?),
      lastSeenAt: _parseDate(json['last_seen_at'] as String?),
    );
  }

  AppUserDevice copyWith({
    String? deviceId,
    String? keysetId,
    String? deviceName,
    String? platform,
    String? identityPublicKey,
    String? keyAlgorithm,
    String? pqcPublicKey,
    String? pqcAlgorithm,
    String? pqcSigningPublicKey,
    String? pqcSigningAlgorithm,
    String? status,
    String? profileFingerprint,
    String? revokedReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? firstSeenAt,
    DateTime? lastSeenAt,
  }) {
    return AppUserDevice(
      deviceId: deviceId ?? this.deviceId,
      keysetId: keysetId ?? this.keysetId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      keyAlgorithm: keyAlgorithm ?? this.keyAlgorithm,
      pqcPublicKey: pqcPublicKey ?? this.pqcPublicKey,
      pqcAlgorithm: pqcAlgorithm ?? this.pqcAlgorithm,
      pqcSigningPublicKey: pqcSigningPublicKey ?? this.pqcSigningPublicKey,
      pqcSigningAlgorithm: pqcSigningAlgorithm ?? this.pqcSigningAlgorithm,
      status: status ?? this.status,
      profileFingerprint: profileFingerprint ?? this.profileFingerprint,
      revokedReason: revokedReason ?? this.revokedReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
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

  bool get hasUsablePqcDeviceKey => preferredPqcDevice != null;

  List<AppUserDevice> get usableX25519Devices =>
      activeDevices.where((device) => device.hasUsableX25519Key).toList();

  List<AppUserDevice> get activeDevices =>
      devices.where((device) => device.isActive).toList();

  AppUserDevice? get preferredX25519Device {
    for (final device in usableX25519Devices) {
      if (device.hasUsableX25519Key) {
        return device;
      }
    }
    return null;
  }

  AppUserDevice? get preferredPqcDevice {
    for (final device in activeDevices) {
      if (device.hasUsableMlKemKey && device.hasUsableMlDsaKey) {
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
