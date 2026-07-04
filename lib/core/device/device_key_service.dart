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

  Future<DeviceKeyMaterial> getOrCreateKeyMaterial() async {
    try {
      final existingPublicKey = await _secretStore.read(_publicKeyKey);
      final existingPrivateKey = await _secretStore.read(_privateKeyKey);
      final existingAlgorithm =
          await _secretStore.read(_algorithmKey) ?? _defaultAlgorithm;

      if (existingPublicKey != null &&
          existingPublicKey.isNotEmpty &&
          existingPrivateKey != null &&
          existingPrivateKey.isNotEmpty) {
        return DeviceKeyMaterial(
          publicKey: existingPublicKey,
          privateKey: existingPrivateKey,
          algorithm: existingAlgorithm,
        );
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

    return DeviceKeyMaterial(
      publicKey: publicKey,
      privateKey: privateKey,
      algorithm: _defaultAlgorithm,
    );
  }

  Future<SimpleKeyPair> getIdentityKeyPair() async {
    final keyMaterial = await getOrCreateKeyMaterial();
    final privateKeyBytes = base64Decode(keyMaterial.privateKey);
    return _algorithm.newKeyPairFromSeed(privateKeyBytes);
  }

  Future<void> _clearStoredIdentity() async {
    try {
      await _secretStore.delete(_publicKeyKey);
      await _secretStore.delete(_privateKeyKey);
      await _secretStore.delete(_algorithmKey);
    } on PlatformException {
      await _secretStore.deleteAll();
    }
  }
}
