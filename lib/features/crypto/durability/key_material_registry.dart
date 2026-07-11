import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/device/device_identity_service.dart';
import '../../../core/device/device_key_service.dart';
import '../../../core/device/device_pqc_key_service.dart';
import '../../../core/device/device_pqc_signing_key_service.dart';
import '../../../core/storage/local_secret_store.dart';
import 'crypto_durability_models.dart';

class KeyMaterialRegistry {
  KeyMaterialRegistry({
    this.deviceIdentityService,
    this.deviceKeyService,
    this.devicePqcKeyService,
    this.devicePqcSigningKeyService,
    LocalSecretStore? secretStore,
    Sha256? hashAlgorithm,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _hashAlgorithm = hashAlgorithm ?? Sha256();

  static const _registryKey = 'crypto_keyset_registry_v1';
  static const _keyPrefix = 'crypto_keyset_entry_v1';

  final DeviceIdentityService? deviceIdentityService;
  final DeviceKeyService? deviceKeyService;
  final DevicePqcKeyService? devicePqcKeyService;
  final DevicePqcSigningKeyService? devicePqcSigningKeyService;
  final LocalSecretStore _secretStore;
  final Sha256 _hashAlgorithm;

  Future<KeysetSnapshot> ensureCurrentKeysetRegistered() async {
    final deviceIdentityService = this.deviceIdentityService;
    final deviceKeyService = this.deviceKeyService;
    final devicePqcKeyService = this.devicePqcKeyService;
    final devicePqcSigningKeyService = this.devicePqcSigningKeyService;
    if (deviceIdentityService == null ||
        deviceKeyService == null ||
        devicePqcKeyService == null ||
        devicePqcSigningKeyService == null) {
      throw StateError('Current device services are not configured.');
    }
    final deviceIdentity = await deviceIdentityService.getIdentity();
    final identity = await deviceKeyService.getOrCreateKeyMaterial();
    final pqc = await devicePqcKeyService.getOrCreateKeyMaterial();
    final signing = await devicePqcSigningKeyService.getOrCreateKeyMaterial();
    final keysetId = await _deriveKeysetId(
      deviceId: deviceIdentity.id,
      identityPublicKey: identity.publicKey,
      pqcPublicKey: pqc.publicKey,
      signingPublicKey: signing.publicKey,
    );
    final existing = await readKeyset(keysetId);
    if (existing != null) {
      if (existing.status != 'active') {
        final reactivated = existing.copyWith(status: 'active');
        await _writeKeyset(reactivated);
        return reactivated;
      }
      return existing;
    }
    final snapshot = KeysetSnapshot(
      keysetId: keysetId,
      deviceId: deviceIdentity.id,
      identityAlgorithm: identity.algorithm,
      identityPublicKey: identity.publicKey,
      identityPrivateKey: identity.privateKey,
      pqcAlgorithm: pqc.algorithm,
      pqcPublicKey: pqc.publicKey,
      pqcSecretKey: pqc.secretKey,
      pqcSigningAlgorithm: signing.algorithm,
      pqcSigningPublicKey: signing.publicKey,
      pqcSigningSecretKey: signing.secretKey,
      status: 'active',
      createdAt: DateTime.now().toUtc(),
    );
    await _writeKeyset(snapshot);
    return snapshot;
  }

  Future<List<KeysetSnapshot>> readAllKeysets() async {
    final ids = await _readRegistry();
    final snapshots = <KeysetSnapshot>[];
    for (final id in ids) {
      final snapshot = await readKeyset(id);
      if (snapshot != null) {
        snapshots.add(snapshot);
      }
    }
    snapshots.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return snapshots;
  }

  Future<List<KeysetSnapshot>> readHistoricalDecryptKeysets() async {
    final snapshots = await readAllKeysets();
    return snapshots.where((item) => item.isHistoricalReadEnabled).toList();
  }

  Future<KeysetSnapshot?> readKeyset(String keysetId) async {
    final raw = await _secretStore.read(_storageKey(keysetId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return KeysetSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> importKeysets(List<KeysetSnapshot> snapshots) async {
    for (final snapshot in snapshots) {
      final existing = await readKeyset(snapshot.keysetId);
      if (existing != null) {
        continue;
      }
      await _writeKeyset(
        snapshot.copyWith(
          status: snapshot.status == 'active' ? 'restored' : snapshot.status,
          restoredAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<HistoricalDecryptCheck> historicalDecryptCheck() async {
    final snapshots = await readHistoricalDecryptKeysets();
    return HistoricalDecryptCheck(
      hasHistoricalCapability: snapshots.isNotEmpty,
      availableKeysets: snapshots.length,
    );
  }

  Future<String> _deriveKeysetId({
    required String deviceId,
    required String identityPublicKey,
    required String pqcPublicKey,
    required String signingPublicKey,
  }) async {
    final digest = await _hashAlgorithm.hash(
      utf8.encode(
        '$deviceId|$identityPublicKey|$pqcPublicKey|$signingPublicKey',
      ),
    );
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _writeKeyset(KeysetSnapshot snapshot) async {
    await _secretStore.write(
      key: _storageKey(snapshot.keysetId),
      value: jsonEncode(snapshot.toJson()),
    );
    final current = await _readRegistry();
    if (!current.contains(snapshot.keysetId)) {
      await _secretStore.write(
        key: _registryKey,
        value: jsonEncode([...current, snapshot.keysetId]),
      );
    }
  }

  Future<List<String>> _readRegistry() async {
    final raw = await _secretStore.read(_registryKey);
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.cast<String>();
  }

  String _storageKey(String keysetId) => '${_keyPrefix}_$keysetId';
}
