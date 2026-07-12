import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../storage/local_secret_store.dart';

class DeviceKeyMaterial {
  const DeviceKeyMaterial({
    required this.publicKey,
    required this.privateKey,
    required this.algorithm,
  });

  final String publicKey;
  final String privateKey;
  final String algorithm;
}

class DeviceKeyService {
  DeviceKeyService({LocalSecretStore? secretStore, X25519? algorithm})
    : _secretStore = secretStore ?? LocalSecretStore(),
      _algorithm = algorithm ?? X25519();

  static const _publicKeyKey = 'identity_public_key';
  static const _privateKeyKey = 'identity_private_key';
  static const _algorithmKey = 'identity_key_algorithm';
  static const _defaultAlgorithm = 'x25519';

  final LocalSecretStore _secretStore;
  final X25519 _algorithm;
  DeviceKeyMaterial? _cachedMaterial;
  SimpleKeyPair? _cachedKeyPair;

  Future<DeviceKeyMaterial> getOrCreateKeyMaterial() async {
    final cachedMaterial = _cachedMaterial;
    if (cachedMaterial != null) {
      return cachedMaterial;
    }
    try {
      final existingPublicKey = await _secretStore.read(_publicKeyKey);
      final existingPrivateKey = await _secretStore.read(_privateKeyKey);
      final existingAlgorithm =
          await _secretStore.read(_algorithmKey) ?? _defaultAlgorithm;

      if (existingPublicKey != null &&
          existingPublicKey.isNotEmpty &&
          existingPrivateKey != null &&
          existingPrivateKey.isNotEmpty) {
        final material = DeviceKeyMaterial(
          publicKey: existingPublicKey,
          privateKey: existingPrivateKey,
          algorithm: existingAlgorithm,
        );
        _cachedMaterial = material;
        return material;
      }
    } on PlatformException {
      await _clearStoredIdentity();
    }

    final keyPair = await _algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    final publicKey = base64Encode(keyPairData.publicKey.bytes);
    final privateKey = base64Encode(privateKeyBytes);

    try {
      await _secretStore.write(key: _publicKeyKey, value: publicKey);
      await _secretStore.write(key: _privateKeyKey, value: privateKey);
      await _secretStore.write(key: _algorithmKey, value: _defaultAlgorithm);
    } on PlatformException {
      await _clearStoredIdentity();
      await _secretStore.write(key: _publicKeyKey, value: publicKey);
      await _secretStore.write(key: _privateKeyKey, value: privateKey);
      await _secretStore.write(key: _algorithmKey, value: _defaultAlgorithm);
    }

    final material = DeviceKeyMaterial(
      publicKey: publicKey,
      privateKey: privateKey,
      algorithm: _defaultAlgorithm,
    );
    _cachedMaterial = material;
    _cachedKeyPair = null;
    return material;
  }

  Future<SimpleKeyPair> getIdentityKeyPair() async {
    final cachedKeyPair = _cachedKeyPair;
    if (cachedKeyPair != null) {
      return cachedKeyPair;
    }
    final keyMaterial = await getOrCreateKeyMaterial();
    final privateKeyBytes = base64Decode(keyMaterial.privateKey);
    final publicKeyBytes = base64Decode(keyMaterial.publicKey);
    final keyPair = SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    _cachedKeyPair = keyPair;
    return keyPair;
  }

  Future<void> _clearStoredIdentity() async {
    _cachedMaterial = null;
    _cachedKeyPair = null;
    try {
      await _secretStore.delete(_publicKeyKey);
      await _secretStore.delete(_privateKeyKey);
      await _secretStore.delete(_algorithmKey);
    } on PlatformException {
      await _secretStore.deleteAll();
    }
  }
}
