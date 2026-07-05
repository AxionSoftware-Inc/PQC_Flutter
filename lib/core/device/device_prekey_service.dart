import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../storage/local_secret_store.dart';

class DevicePreKeyMaterial {
  const DevicePreKeyMaterial({
    required this.keyId,
    required this.publicKey,
    required this.privateKey,
  });

  final String keyId;
  final String publicKey;
  final String privateKey;

  Map<String, dynamic> toPublicJson() {
    return {'key_id': keyId, 'public_key': publicKey};
  }
}

class DevicePreKeyService {
  DevicePreKeyService({
    LocalSecretStore? secretStore,
    X25519? algorithm,
    Uuid? uuid,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _algorithm = algorithm ?? X25519(),
       _uuid = uuid ?? const Uuid();

  static const _registryKey = 'device_prekey_registry';
  static const _privatePrefix = 'device_prekey_private';
  static const _defaultBatchSize = 12;

  final LocalSecretStore _secretStore;
  final X25519 _algorithm;
  final Uuid _uuid;

  Future<List<Map<String, dynamic>>> ensurePreKeys({
    int minimumCount = _defaultBatchSize,
  }) async {
    final existing = await _readRegistry();
    if (existing.length >= minimumCount) {
      return existing.map((item) => item.toPublicJson()).toList();
    }

    final next = [...existing];
    final missingCount = minimumCount - existing.length;
    for (var index = 0; index < missingCount; index++) {
      final keyPair = await _algorithm.newKeyPair();
      final keyPairData = await keyPair.extract();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final material = DevicePreKeyMaterial(
        keyId: _uuid.v4(),
        publicKey: base64Encode(keyPairData.publicKey.bytes),
        privateKey: base64Encode(privateKeyBytes),
      );
      next.add(material);
      await _secretStore.write(
        key: _privateStorageKey(material.keyId),
        value: material.privateKey,
      );
    }

    await _writeRegistry(next);
    return next.map((item) => item.toPublicJson()).toList();
  }

  Future<void> removePreKey(String keyId) async {
    final registry = await _readRegistry();
    final next = registry.where((item) => item.keyId != keyId).toList();
    await _writeRegistry(next);
    await _secretStore.delete(_privateStorageKey(keyId));
  }

  Future<SimpleKeyPair?> takePreKeyPair(String keyId) async {
    final privateKey = await _secretStore.read(_privateStorageKey(keyId));
    if (privateKey == null || privateKey.isEmpty) {
      return null;
    }
    return _algorithm.newKeyPairFromSeed(base64Decode(privateKey));
  }

  Future<List<DevicePreKeyMaterial>> _readRegistry() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_registryKey);
    if (raw == null || raw.isEmpty) {
      return <DevicePreKeyMaterial>[];
    }

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) {
      final json = item as Map<String, dynamic>;
      return DevicePreKeyMaterial(
        keyId: json['key_id'] as String,
        publicKey: json['public_key'] as String,
        privateKey: '',
      );
    }).toList();
  }

  Future<void> _writeRegistry(List<DevicePreKeyMaterial> items) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _registryKey,
      jsonEncode(
        items
            .map((item) => {'key_id': item.keyId, 'public_key': item.publicKey})
            .toList(),
      ),
    );
  }

  String _privateStorageKey(String keyId) => '${_privatePrefix}_$keyId';
}
