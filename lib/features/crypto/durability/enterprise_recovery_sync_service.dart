import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/device/device_identity_service.dart';
import '../../../core/network/api_client.dart';
import 'crypto_core_facade.dart';
import 'package:crypto_core/crypto_core.dart' show RecoveryManifestIntegrity;

/// Publishes an immutable recovery snapshot after every successful encrypted
/// send. Failures are deliberately retained for the next lifecycle retry and
/// never change the delivery status of an already-sent message.
class EnterpriseRecoverySyncService {
  EnterpriseRecoverySyncService({
    required this.apiClient,
    required this.cryptoCoreFacade,
    required this.deviceIdentityService,
  });

  final ApiClient apiClient;
  final CryptoCoreFacade cryptoCoreFacade;
  final DeviceIdentityService deviceIdentityService;
  Future<void>? _inFlight;
  String? _lastPublishedPayloadHash;
  String? _lastVerifiedPayloadHash;

  Future<void> publishInBackground() {
    return _inFlight ??= _publishAndVerify().whenComplete(
      () => _inFlight = null,
    );
  }

  /// Restores escrowed keysets during login/reinstall without requiring a
  /// separate settings action. Existing local keysets are never overwritten.
  Future<bool> restoreIfAvailable() async {
    try {
      final response = await apiClient.get('/users/me/crypto-recovery');
      if (response is! Map || response['available'] != true) return false;
      final records = response['records'] as List<dynamic>? ?? const [];
      final payloads = records
          .whereType<Map>()
          .map((record) => record['payload'])
          .whereType<String>()
          .where((payload) => payload.isNotEmpty)
          .toList(growable: false);
      await RecoveryManifestIntegrity.verify(
        payloads: payloads,
        expectedMerkleRoot: response['merkle_root'] as String? ?? '',
      );
      var imported = false;
      for (final record in records) {
        if (record is! Map) continue;
        final payload = record['payload'] as String?;
        if (payload == null || payload.isEmpty) continue;
        await cryptoCoreFacade.importEnterpriseRecoveryManifest(payload);
        imported = true;
      }
      return imported;
    } on ApiException {
      // Recovery is best-effort during login; ordinary login must still work
      // when an account has no manifest yet or the service is unavailable.
      return false;
    }
  }

  Future<void> _publish(_RecoverySnapshot snapshot) async {
    if (_lastPublishedPayloadHash == snapshot.payloadHash) {
      return;
    }
    final index = await apiClient.get('/users/me/crypto-recovery');
    var sequence = index is Map && index['available'] == true
        ? index['sequence'] as int? ?? 0
        : 0;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await apiClient.put('/users/me/crypto-recovery', {
          'schema_version': 2,
          'payload': snapshot.payload,
          'source_device_id': snapshot.deviceId,
          'expected_sequence': sequence,
        });
        _lastPublishedPayloadHash = snapshot.payloadHash;
        return;
      } on ApiException catch (error) {
        if (error.statusCode != 412 || attempt == 1) rethrow;
        final latest = await apiClient.get('/users/me/crypto-recovery');
        sequence = latest is Map ? latest['sequence'] as int? ?? 0 : 0;
      }
    }
  }

  /// A successful PUT only proves that the request reached the server.  The
  /// send pipeline may report recovery as durable only after a fresh GET has
  /// proven that the current keyset is present in the authenticated manifest.
  Future<void> _publishAndVerify() async {
    final snapshot = await _createSnapshot();
    // The send path invokes this after every message. A verified snapshot is
    // immutable for a stable keyset, so repeating a server PUT + KMS-backed
    // GET on every text message adds latency without adding protection. Any
    // key rotation, group rekey, or recovery-state change changes this hash
    // and automatically requires a new round-trip.
    if (_lastVerifiedPayloadHash == snapshot.payloadHash) {
      return;
    }
    await _publish(snapshot);
    final response = await apiClient.get('/users/me/crypto-recovery');
    if (response is! Map || response['available'] != true) {
      throw StateError('Recovery vault did not retain the current keyset.');
    }
    final records = response['records'] as List<dynamic>? ?? const [];
    final payloads = records
        .whereType<Map>()
        .map((record) => record['payload'])
        .whereType<String>()
        .where((payload) => payload.isNotEmpty)
        .toList(growable: false);
    await RecoveryManifestIntegrity.verify(
      payloads: payloads,
      expectedMerkleRoot: response['merkle_root'] as String? ?? '',
    );
    final containsCurrent = payloads.any((payload) {
      try {
        final document = jsonDecode(payload) as Map<String, dynamic>;
        final keysets = document['keysets'] as List<dynamic>? ?? const [];
        return keysets.whereType<Map>().any(
          (keyset) => keyset['keyset_id'] == snapshot.keysetId,
        );
      } catch (_) {
        return false;
      }
    });
    if (!containsCurrent) {
      throw StateError('Recovery vault is missing the current keyset.');
    }
    _lastVerifiedPayloadHash = snapshot.payloadHash;
  }

  Future<_RecoverySnapshot> _createSnapshot() async {
    final keyset = await cryptoCoreFacade.keyMaterialRegistry
        .ensureCurrentKeysetRegistered();
    final payload = await cryptoCoreFacade.exportEnterpriseRecoveryManifest();
    final payloadHash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(payload))).bytes,
    ).replaceAll('=', '');
    final deviceId = (await deviceIdentityService.getIdentity()).id;
    return _RecoverySnapshot(
      deviceId: deviceId,
      keysetId: keyset.keysetId,
      payload: payload,
      payloadHash: payloadHash,
    );
  }
}

class _RecoverySnapshot {
  const _RecoverySnapshot({
    required this.deviceId,
    required this.keysetId,
    required this.payload,
    required this.payloadHash,
  });

  final String deviceId;
  final String keysetId;
  final String payload;
  final String payloadHash;
}
