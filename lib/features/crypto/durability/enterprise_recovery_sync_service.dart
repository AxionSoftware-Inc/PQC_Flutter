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

  Future<void> publishInBackground() {
    return _inFlight ??= _publish().whenComplete(() => _inFlight = null);
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

  Future<void> _publish() async {
    final deviceId = (await deviceIdentityService.getIdentity()).id;
    final payload = await cryptoCoreFacade.exportEnterpriseRecoveryManifest();
    final payloadHash = base64UrlEncode(
      (await Sha256().hash(utf8.encode(payload))).bytes,
    ).replaceAll('=', '');
    if (_lastPublishedPayloadHash == payloadHash) {
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
          'payload': payload,
          'source_device_id': deviceId,
          'expected_sequence': sequence,
        });
        _lastPublishedPayloadHash = payloadHash;
        return;
      } on ApiException catch (error) {
        if (error.statusCode != 412 || attempt == 1) rethrow;
        final latest = await apiClient.get('/users/me/crypto-recovery');
        sequence = latest is Map ? latest['sequence'] as int? ?? 0 : 0;
      }
    }
  }
}
