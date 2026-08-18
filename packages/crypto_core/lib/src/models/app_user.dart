import 'dart:convert';

import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';

class AppUserDevice {
  const AppUserDevice({
    required this.deviceId,
    this.keysetId = '',
    this.keysetBindingId = '',
    required this.deviceName,
    required this.platform,
    required this.identityPublicKey,
    required this.keyAlgorithm,
    this.pqcPublicKey = '',
    this.pqcAlgorithm = '',
    this.pqcSigningPublicKey = '',
    this.pqcSigningAlgorithm = '',
    this.supportedProtocols = const ['v2'],
    this.status = 'active',
    this.profileFingerprint = '',
    this.revokedReason = '',
    this.createdAt,
    this.updatedAt,
    this.firstSeenAt,
    this.lastSeenAt,
  });

  final String deviceId;

  /// Frozen V2 keyset identity. It is optional for legacy device records;
  /// V3 uses [v3KeysetId] so both PQC public keys are bound.
  final String keysetId;
  final String keysetBindingId;
  final String deviceName;
  final String platform;
  final String identityPublicKey;
  final String keyAlgorithm;
  final String pqcPublicKey;
  final String pqcAlgorithm;
  final String pqcSigningPublicKey;
  final String pqcSigningAlgorithm;

  /// Protocols this specific installation can decode and safely receive.
  /// Legacy API responses intentionally default to V2 only.
  final List<String> supportedProtocols;
  final String status;
  final String profileFingerprint;
  final String revokedReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;

  /// V2's [keysetId] is frozen and intentionally binds only the KEM key.
  /// V3 uses a binding that covers both the KEM and signing public keys.
  String get v3KeysetId {
    if (deviceId.isEmpty ||
        pqcPublicKey.isEmpty ||
        pqcSigningPublicKey.isEmpty) {
      return keysetId;
    }
    final computed = computeKeysetBindingId(
      deviceId,
      pqcPublicKey,
      pqcSigningPublicKey,
    );
    if (keysetBindingId.isNotEmpty && keysetBindingId != computed) {
      return '';
    }
    return computed;
  }

  bool get isActive => status == 'active';

  bool supportsProtocol(String protocolId) =>
      supportedProtocols.contains(protocolId.trim().toLowerCase());

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
      final bytes = base64Decode(value);
      if (bytes.length != 1184) {
        return false;
      }

      // ML-KEM-768 encodes three polynomials in the first 1152 bytes. Every
      // pair of coefficients occupies three bytes and must be canonical
      // modulo q=3329. A length-only check lets corrupted/random device keys
      // reach encapsulation and fail during message send.
      for (var offset = 0; offset < 1152; offset += 3) {
        final first = bytes[offset] | ((bytes[offset + 1] & 0x0f) << 8);
        final second = (bytes[offset + 1] >> 4) | (bytes[offset + 2] << 4);
        if (first >= 3329 || second >= 3329) {
          return false;
        }
      }
      return true;
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
      keysetBindingId: json['keyset_binding_id'] as String? ?? '',
      deviceName: json['device_name'] as String? ?? '',
      platform: json['platform'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      keyAlgorithm: json['key_algorithm'] as String? ?? '',
      pqcPublicKey: json['pqc_public_key'] as String? ?? '',
      pqcAlgorithm: json['pqc_algorithm'] as String? ?? '',
      pqcSigningPublicKey: json['pqc_signing_public_key'] as String? ?? '',
      pqcSigningAlgorithm: json['pqc_signing_algorithm'] as String? ?? '',
      supportedProtocols: _parseSupportedProtocols(json['supported_protocols']),
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
    String? keysetBindingId,
    String? deviceName,
    String? platform,
    String? identityPublicKey,
    String? keyAlgorithm,
    String? pqcPublicKey,
    String? pqcAlgorithm,
    String? pqcSigningPublicKey,
    String? pqcSigningAlgorithm,
    List<String>? supportedProtocols,
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
      keysetBindingId: keysetBindingId ?? this.keysetBindingId,
      deviceName: deviceName ?? this.deviceName,
      platform: platform ?? this.platform,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      keyAlgorithm: keyAlgorithm ?? this.keyAlgorithm,
      pqcPublicKey: pqcPublicKey ?? this.pqcPublicKey,
      pqcAlgorithm: pqcAlgorithm ?? this.pqcAlgorithm,
      pqcSigningPublicKey: pqcSigningPublicKey ?? this.pqcSigningPublicKey,
      pqcSigningAlgorithm: pqcSigningAlgorithm ?? this.pqcSigningAlgorithm,
      supportedProtocols: supportedProtocols ?? this.supportedProtocols,
      status: status ?? this.status,
      profileFingerprint: profileFingerprint ?? this.profileFingerprint,
      revokedReason: revokedReason ?? this.revokedReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  static List<String> _parseSupportedProtocols(Object? value) {
    if (value is! List) {
      return const ['v2'];
    }
    final supported = value
        .whereType<String>()
        .map((item) => item.trim().toLowerCase())
        .map((item) => item == 'v25' || item == 'v2_5' ? 'v2.5' : item)
        .where((item) => const {'v2', 'v2.5', 'v3'}.contains(item))
        .toSet();
    if (supported.isEmpty) {
      return const ['v2'];
    }
    if (supported.contains('v3')) {
      supported.addAll(const ['v2', 'v2.5']);
    } else if (supported.contains('v2.5')) {
      supported.add('v2');
    }
    return [
      for (final item in const ['v2', 'v2.5', 'v3'])
        if (supported.contains(item)) item,
    ];
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
    this.avatarUrl = '',
    this.role = 'member',
    this.roleLabel = 'Xodim',
    this.canManageRole = false,
    this.workspaceMemberId,
  });

  final int id;
  final String username;
  final String displayName;
  final List<AppUserDevice> devices;
  final String avatarUrl;
  final String role;
  final String roleLabel;
  final bool canManageRole;
  final int? workspaceMemberId;

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
      avatarUrl: json['avatar_url'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      roleLabel: json['role_label'] as String? ?? 'Xodim',
      canManageRole: json['can_manage_role'] as bool? ?? false,
      workspaceMemberId: json['workspace_member_id'] as int?,
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
    String? avatarUrl,
    String? role,
    String? roleLabel,
    bool? canManageRole,
    int? workspaceMemberId,
  }) {
    return AppUser(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      devices: devices ?? this.devices,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      roleLabel: roleLabel ?? this.roleLabel,
      canManageRole: canManageRole ?? this.canManageRole,
      workspaceMemberId: workspaceMemberId ?? this.workspaceMemberId,
    );
  }
}
