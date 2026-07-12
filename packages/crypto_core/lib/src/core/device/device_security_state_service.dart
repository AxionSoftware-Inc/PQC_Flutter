import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'device_identity_service.dart';
import 'device_key_service.dart';
import 'device_pqc_key_service.dart';
import 'device_pqc_signing_key_service.dart';

class DeviceSecurityStateSnapshot {
  const DeviceSecurityStateSnapshot({
    required this.deviceId,
    required this.identityPublicKey,
    required this.pqcPublicKey,
    required this.pqcSigningPublicKey,
  });

  final String deviceId;
  final String identityPublicKey;
  final String pqcPublicKey;
  final String pqcSigningPublicKey;

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'identity_public_key': identityPublicKey,
      'pqc_public_key': pqcPublicKey,
      'pqc_signing_public_key': pqcSigningPublicKey,
    };
  }

  factory DeviceSecurityStateSnapshot.fromJson(Map<String, dynamic> json) {
    return DeviceSecurityStateSnapshot(
      deviceId: json['device_id'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      pqcPublicKey: json['pqc_public_key'] as String? ?? '',
      pqcSigningPublicKey: json['pqc_signing_public_key'] as String? ?? '',
    );
  }
}

class DeviceSecurityStateResolution {
  const DeviceSecurityStateResolution({
    required this.deviceIdentity,
    required this.identityKeyMaterial,
    required this.pqcKeyMaterial,
    required this.pqcSigningKeyMaterial,
    required this.didRotateInstallation,
  });

  final DeviceIdentity deviceIdentity;
  final DeviceKeyMaterial identityKeyMaterial;
  final DevicePqcKeyMaterial? pqcKeyMaterial;
  final DevicePqcSigningKeyMaterial pqcSigningKeyMaterial;
  final bool didRotateInstallation;
}

class DeviceSecurityStateService {
  DeviceSecurityStateService();

  static const _snapshotKey = 'device_security_state_snapshot_v1';

  Future<DeviceSecurityStateResolution> ensureConsistentState({
    required DeviceIdentityService deviceIdentityService,
    required DeviceKeyService deviceKeyService,
    required DevicePqcKeyService devicePqcKeyService,
    required DevicePqcSigningKeyService devicePqcSigningKeyService,
  }) async {
    var deviceIdentity = await deviceIdentityService.getIdentity();
    final identityKeyMaterial = await deviceKeyService.getOrCreateKeyMaterial();
    final pqcSigningKeyMaterial = await devicePqcSigningKeyService
        .getOrCreateKeyMaterial();
    final pqcKeyMaterial = devicePqcKeyService.isSupportedOnCurrentPlatform
        ? await devicePqcKeyService.getOrCreateKeyMaterial()
        : null;

    final currentSnapshot = DeviceSecurityStateSnapshot(
      deviceId: deviceIdentity.id,
      identityPublicKey: identityKeyMaterial.publicKey,
      pqcPublicKey: pqcKeyMaterial?.publicKey ?? '',
      pqcSigningPublicKey: pqcSigningKeyMaterial.publicKey,
    );
    final previousSnapshot = await _readSnapshot();

    if (previousSnapshot == null) {
      await _writeSnapshot(currentSnapshot);
      return DeviceSecurityStateResolution(
        deviceIdentity: deviceIdentity,
        identityKeyMaterial: identityKeyMaterial,
        pqcKeyMaterial: pqcKeyMaterial,
        pqcSigningKeyMaterial: pqcSigningKeyMaterial,
        didRotateInstallation: false,
      );
    }

    final sameDeviceId = previousSnapshot.deviceId == currentSnapshot.deviceId;
    final keyMaterialChanged =
        previousSnapshot.identityPublicKey !=
            currentSnapshot.identityPublicKey ||
        previousSnapshot.pqcPublicKey != currentSnapshot.pqcPublicKey ||
        previousSnapshot.pqcSigningPublicKey !=
            currentSnapshot.pqcSigningPublicKey;

    if (sameDeviceId && keyMaterialChanged) {
      deviceIdentity = await deviceIdentityService.rotateIdentity();
      await _writeSnapshot(
        DeviceSecurityStateSnapshot(
          deviceId: deviceIdentity.id,
          identityPublicKey: identityKeyMaterial.publicKey,
          pqcPublicKey: pqcKeyMaterial?.publicKey ?? '',
          pqcSigningPublicKey: pqcSigningKeyMaterial.publicKey,
        ),
      );
      return DeviceSecurityStateResolution(
        deviceIdentity: deviceIdentity,
        identityKeyMaterial: identityKeyMaterial,
        pqcKeyMaterial: pqcKeyMaterial,
        pqcSigningKeyMaterial: pqcSigningKeyMaterial,
        didRotateInstallation: true,
      );
    }

    await _writeSnapshot(currentSnapshot);
    return DeviceSecurityStateResolution(
      deviceIdentity: deviceIdentity,
      identityKeyMaterial: identityKeyMaterial,
      pqcKeyMaterial: pqcKeyMaterial,
      pqcSigningKeyMaterial: pqcSigningKeyMaterial,
      didRotateInstallation: false,
    );
  }

  Future<DeviceSecurityStateSnapshot?> _readSnapshot() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return DeviceSecurityStateSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSnapshot(DeviceSecurityStateSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_snapshotKey, jsonEncode(snapshot.toJson()));
  }
}
