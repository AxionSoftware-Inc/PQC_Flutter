import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'package:crypto_core/src/core/device/device_identity_service.dart';
import 'package:crypto_core/src/core/device/device_key_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_key_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_signing_key_service.dart';
import 'package:crypto_core/src/core/storage/local_secret_store.dart';
import 'crypto_durability_models.dart';
import 'key_storage_integrity.dart';

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
  static const _pendingKey = 'crypto_keyset_registry_pending_v1';

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
      pqcPublicKey: pqc.publicKey,
    );
    final existing = await readKeyset(keysetId);
    if (existing != null) {
      if (existing.integrityHash == null) {
        final sealed = await KeyStorageIntegrity.seal(existing);
        await _writeKeyset(sealed);
        return sealed;
      }
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
    final snapshot = KeysetSnapshot.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    await KeyStorageIntegrity.verify(snapshot);
    return snapshot;
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
    required String pqcPublicKey,
  }) async {
    final digest = await _hashAlgorithm.hash(
      utf8.encode('$deviceId|$pqcPublicKey'),
    );
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  Future<void> _writeKeyset(KeysetSnapshot snapshot) async {
    // Recompute after status/restore transitions as those fields are part of
    // the authenticated keyset record.
    final sealed = await KeyStorageIntegrity.seal(snapshot);
    // Two-phase registry update: if the process dies between the key write
    // and registry write, the pending id is still discovered on next boot.
    await _secretStore.write(key: _pendingKey, value: sealed.keysetId);
    await _secretStore.write(
      key: _storageKey(snapshot.keysetId),
      value: jsonEncode(sealed.toJson()),
    );
    final current = await _readRegistry(includePending: false);
    if (!current.contains(snapshot.keysetId)) {
      await _secretStore.write(
        key: _registryKey,
        value: jsonEncode([...current, snapshot.keysetId]),
      );
    }
    await _secretStore.delete(_pendingKey);
  }

  Future<List<String>> _readRegistry({bool includePending = true}) async {
    final raw = await _secretStore.read(_registryKey);
    final ids = raw == null || raw.isEmpty
        ? <String>[]
        : (jsonDecode(raw) as List<dynamic>).cast<String>();
    if (includePending) {
      final pending = await _secretStore.read(_pendingKey);
      if (pending != null && pending.isNotEmpty && !ids.contains(pending)) {
        ids.add(pending);
      }
    }
    return ids;
  }

  String _storageKey(String keysetId) => '${_keyPrefix}_$keysetId';
}
