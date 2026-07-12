import 'dart:convert';

import 'package:crypto_core/src/models/session_user.dart';
import 'package:crypto_core/src/network/api_client.dart';
import '../storage/local_secret_store.dart';
import 'device_identity_service.dart';
import 'device_key_service.dart';
import 'device_pqc_key_service.dart';
import 'device_pqc_signing_key_service.dart';
import 'device_security_state_service.dart';

enum DeviceInstallationStatus {
  active,
  needsRegistration,
  rotated,
  revoked,
}

class DeviceProfileSnapshot {
  const DeviceProfileSnapshot({
    required this.deviceId,
    required this.identityAlgorithm,
    required this.identityPublicKey,
    required this.pqcAlgorithm,
    required this.pqcPublicKey,
    required this.pqcSigningAlgorithm,
    required this.pqcSigningPublicKey,
    required this.profileVersion,
    required this.integrityMarker,
    required this.installationStatus,
    this.serverProfileFingerprint = '',
    this.lastSyncedAt,
  });

  final String deviceId;
  final String identityAlgorithm;
  final String identityPublicKey;
  final String pqcAlgorithm;
  final String pqcPublicKey;
  final String pqcSigningAlgorithm;
  final String pqcSigningPublicKey;
  final int profileVersion;
  final String integrityMarker;
  final DeviceInstallationStatus installationStatus;
  final String serverProfileFingerprint;
  final DateTime? lastSyncedAt;

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'identity_algorithm': identityAlgorithm,
      'identity_public_key': identityPublicKey,
      'pqc_algorithm': pqcAlgorithm,
      'pqc_public_key': pqcPublicKey,
      'pqc_signing_algorithm': pqcSigningAlgorithm,
      'pqc_signing_public_key': pqcSigningPublicKey,
      'profile_version': profileVersion,
      'integrity_marker': integrityMarker,
      'installation_status': installationStatus.name,
      'server_profile_fingerprint': serverProfileFingerprint,
      'last_synced_at': lastSyncedAt?.toIso8601String(),
    };
  }

  factory DeviceProfileSnapshot.fromJson(Map<String, dynamic> json) {
    return DeviceProfileSnapshot(
      deviceId: json['device_id'] as String? ?? '',
      identityAlgorithm: json['identity_algorithm'] as String? ?? '',
      identityPublicKey: json['identity_public_key'] as String? ?? '',
      pqcAlgorithm: json['pqc_algorithm'] as String? ?? '',
      pqcPublicKey: json['pqc_public_key'] as String? ?? '',
      pqcSigningAlgorithm: json['pqc_signing_algorithm'] as String? ?? '',
      pqcSigningPublicKey: json['pqc_signing_public_key'] as String? ?? '',
      profileVersion: json['profile_version'] as int? ?? 1,
      integrityMarker: json['integrity_marker'] as String? ?? '',
      installationStatus: DeviceInstallationStatus.values.firstWhere(
        (item) => item.name == (json['installation_status'] as String? ?? ''),
        orElse: () => DeviceInstallationStatus.needsRegistration,
      ),
      serverProfileFingerprint:
          json['server_profile_fingerprint'] as String? ?? '',
      lastSyncedAt: DateTime.tryParse(json['last_synced_at'] as String? ?? ''),
    );
  }

  DeviceProfileSnapshot copyWith({
    String? deviceId,
    String? identityAlgorithm,
    String? identityPublicKey,
    String? pqcAlgorithm,
    String? pqcPublicKey,
    String? pqcSigningAlgorithm,
    String? pqcSigningPublicKey,
    int? profileVersion,
    String? integrityMarker,
    DeviceInstallationStatus? installationStatus,
    String? serverProfileFingerprint,
    DateTime? lastSyncedAt,
  }) {
    return DeviceProfileSnapshot(
      deviceId: deviceId ?? this.deviceId,
      identityAlgorithm: identityAlgorithm ?? this.identityAlgorithm,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      pqcAlgorithm: pqcAlgorithm ?? this.pqcAlgorithm,
      pqcPublicKey: pqcPublicKey ?? this.pqcPublicKey,
      pqcSigningAlgorithm: pqcSigningAlgorithm ?? this.pqcSigningAlgorithm,
      pqcSigningPublicKey: pqcSigningPublicKey ?? this.pqcSigningPublicKey,
      profileVersion: profileVersion ?? this.profileVersion,
      integrityMarker: integrityMarker ?? this.integrityMarker,
      installationStatus: installationStatus ?? this.installationStatus,
      serverProfileFingerprint:
          serverProfileFingerprint ?? this.serverProfileFingerprint,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

class DeviceProfileState {
  const DeviceProfileState({
    required this.deviceIdentity,
    required this.identityKeyMaterial,
    required this.pqcKeyMaterial,
    required this.pqcSigningKeyMaterial,
    required this.snapshot,
    required this.didRotateInstallation,
  });

  final DeviceIdentity deviceIdentity;
  final DeviceKeyMaterial identityKeyMaterial;
  final DevicePqcKeyMaterial? pqcKeyMaterial;
  final DevicePqcSigningKeyMaterial pqcSigningKeyMaterial;
  final DeviceProfileSnapshot snapshot;
  final bool didRotateInstallation;
}

class DeviceStateManager {
  DeviceStateManager({
    required this.deviceIdentityService,
    required this.deviceKeyService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    required this.deviceSecurityStateService,
    LocalSecretStore? secretStore,
  }) : _secretStore = secretStore ?? LocalSecretStore();

  static const _snapshotKey = 'device_profile_snapshot_v2';
  static const _profileVersion = 2;

  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final DeviceSecurityStateService deviceSecurityStateService;
  final LocalSecretStore _secretStore;

  DeviceProfileState? _cachedState;

  Future<DeviceProfileState> resolveCurrentDeviceProfile() async {
    final cached = _cachedState;
    if (cached != null) {
      return cached;
    }

    final resolved = await deviceSecurityStateService.ensureConsistentState(
      deviceIdentityService: deviceIdentityService,
      deviceKeyService: deviceKeyService,
      devicePqcKeyService: devicePqcKeyService,
      devicePqcSigningKeyService: devicePqcSigningKeyService,
    );
    final existingSnapshot = await _readSnapshot();
    final snapshot = DeviceProfileSnapshot(
      deviceId: resolved.deviceIdentity.id,
      identityAlgorithm: resolved.identityKeyMaterial.algorithm,
      identityPublicKey: resolved.identityKeyMaterial.publicKey,
      pqcAlgorithm: resolved.pqcKeyMaterial?.algorithm ?? '',
      pqcPublicKey: resolved.pqcKeyMaterial?.publicKey ?? '',
      pqcSigningAlgorithm: resolved.pqcSigningKeyMaterial.algorithm,
      pqcSigningPublicKey: resolved.pqcSigningKeyMaterial.publicKey,
      profileVersion: _profileVersion,
      integrityMarker: _buildIntegrityMarker(
        deviceId: resolved.deviceIdentity.id,
        identityPublicKey: resolved.identityKeyMaterial.publicKey,
        pqcPublicKey: resolved.pqcKeyMaterial?.publicKey ?? '',
        pqcSigningPublicKey: resolved.pqcSigningKeyMaterial.publicKey,
      ),
      installationStatus: resolved.didRotateInstallation
          ? DeviceInstallationStatus.rotated
          : (existingSnapshot?.installationStatus ??
                DeviceInstallationStatus.needsRegistration),
      serverProfileFingerprint:
          existingSnapshot?.serverProfileFingerprint ?? '',
      lastSyncedAt: existingSnapshot?.lastSyncedAt,
    );
    await _writeSnapshot(snapshot);
    final state = DeviceProfileState(
      deviceIdentity: resolved.deviceIdentity,
      identityKeyMaterial: resolved.identityKeyMaterial,
      pqcKeyMaterial: resolved.pqcKeyMaterial,
      pqcSigningKeyMaterial: resolved.pqcSigningKeyMaterial,
      snapshot: snapshot,
      didRotateInstallation: resolved.didRotateInstallation,
    );
    _cachedState = state;
    return state;
  }

  Future<DeviceProfileState> rotateToNewInstallation() async {
    await deviceIdentityService.rotateIdentity();
    _cachedState = null;
    final state = await resolveCurrentDeviceProfile();
    final rotated = state.snapshot.copyWith(
      installationStatus: DeviceInstallationStatus.rotated,
      serverProfileFingerprint: '',
      lastSyncedAt: null,
    );
    await _writeSnapshot(rotated);
    final next = DeviceProfileState(
      deviceIdentity: state.deviceIdentity,
      identityKeyMaterial: state.identityKeyMaterial,
      pqcKeyMaterial: state.pqcKeyMaterial,
      pqcSigningKeyMaterial: state.pqcSigningKeyMaterial,
      snapshot: rotated,
      didRotateInstallation: true,
    );
    _cachedState = next;
    return next;
  }

  Future<void> markDeviceProfileSynced({
    required String serverProfileFingerprint,
    DeviceInstallationStatus installationStatus =
        DeviceInstallationStatus.active,
  }) async {
    final state = await resolveCurrentDeviceProfile();
    final snapshot = state.snapshot.copyWith(
      serverProfileFingerprint: serverProfileFingerprint,
      installationStatus: installationStatus,
      lastSyncedAt: DateTime.now().toUtc(),
    );
    await _writeSnapshot(snapshot);
    _cachedState = DeviceProfileState(
      deviceIdentity: state.deviceIdentity,
      identityKeyMaterial: state.identityKeyMaterial,
      pqcKeyMaterial: state.pqcKeyMaterial,
      pqcSigningKeyMaterial: state.pqcSigningKeyMaterial,
      snapshot: snapshot,
      didRotateInstallation: state.didRotateInstallation,
    );
  }

  Future<void> markRevoked() async {
    final state = await resolveCurrentDeviceProfile();
    final snapshot = state.snapshot.copyWith(
      installationStatus: DeviceInstallationStatus.revoked,
    );
    await _writeSnapshot(snapshot);
    _cachedState = DeviceProfileState(
      deviceIdentity: state.deviceIdentity,
      identityKeyMaterial: state.identityKeyMaterial,
      pqcKeyMaterial: state.pqcKeyMaterial,
      pqcSigningKeyMaterial: state.pqcSigningKeyMaterial,
      snapshot: snapshot,
      didRotateInstallation: state.didRotateInstallation,
    );
  }

  Future<List<String>> listTrustedDevices(SessionUser sessionUser) async {
    return [sessionUser.deviceId].where((item) => item.isNotEmpty).toList();
  }

  Future<void> syncCurrentDeviceProfile({
    required ApiClient apiClient,
    required SessionUser sessionUser,
  }) async {
    final state = await resolveCurrentDeviceProfile();
    apiClient.setDeviceId(state.deviceIdentity.id);
    final response =
        await apiClient.post('/users/me/device/sync', {
              'device_id': state.deviceIdentity.id,
              'device_name': state.deviceIdentity.deviceName,
              'platform': state.deviceIdentity.platform,
              'identity_public_key': state.identityKeyMaterial.publicKey,
              'key_algorithm': state.identityKeyMaterial.algorithm,
              'pqc_public_key': state.pqcKeyMaterial?.publicKey ?? '',
              'pqc_algorithm': state.pqcKeyMaterial?.algorithm ?? '',
              'pqc_signing_public_key': state.pqcSigningKeyMaterial.publicKey,
              'pqc_signing_algorithm': state.pqcSigningKeyMaterial.algorithm,
            })
            as Map<String, dynamic>;
    final serverFingerprint = response['profile_fingerprint'] as String? ?? '';
    final statusValue = response['device_status'] as String? ?? 'active';
    await markDeviceProfileSynced(
      serverProfileFingerprint: serverFingerprint,
      installationStatus: DeviceInstallationStatus.values.firstWhere(
        (item) => item.name == statusValue,
        orElse: () => DeviceInstallationStatus.active,
      ),
    );
    apiClient.setDeviceId(sessionUser.deviceId.isEmpty
        ? state.deviceIdentity.id
        : sessionUser.deviceId);
  }

  Future<DeviceProfileSnapshot?> _readSnapshot() async {
    final raw = await _secretStore.read(_snapshotKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      return DeviceProfileSnapshot.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSnapshot(DeviceProfileSnapshot snapshot) async {
    await _secretStore.write(
      key: _snapshotKey,
      value: jsonEncode(snapshot.toJson()),
    );
  }

  String _buildIntegrityMarker({
    required String deviceId,
    required String identityPublicKey,
    required String pqcPublicKey,
    required String pqcSigningPublicKey,
  }) {
    return base64Encode(
      utf8.encode(
        [
          deviceId,
          identityPublicKey,
          pqcPublicKey,
          pqcSigningPublicKey,
        ].join('|'),
      ),
    );
  }
}
