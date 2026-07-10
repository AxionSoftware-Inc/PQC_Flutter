import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pqcrypto/pqcrypto.dart';

import '../storage/local_secret_store.dart';

class DevicePqcKeyMaterial {
  const DevicePqcKeyMaterial({
    required this.publicKey,
    required this.secretKey,
    required this.algorithm,
  });

  final String publicKey;
  final String secretKey;
  final String algorithm;
}

class DevicePqcKeyService {
  DevicePqcKeyService({LocalSecretStore? secretStore, KyberKem? kem})
    : _secretStore = secretStore ?? LocalSecretStore(),
      _kem = kem ?? PqcKem.kyber768;

  static const algorithmName = 'ml-kem-768';
  static const publicKeyLength = 1184;
  static const secretKeyLength = 2400;
  static const ciphertextLength = 1088;
  static const sharedSecretLength = 32;

  static const _publicKeyKey = 'pqc_public_key';
  static const _secretKeyKey = 'pqc_secret_key';
  static const _algorithmKey = 'pqc_key_algorithm';

  final LocalSecretStore _secretStore;
  final KyberKem _kem;
  DevicePqcKeyMaterial? _cachedMaterial;

  bool get isSupportedOnCurrentPlatform => !kIsWeb;

  Future<DevicePqcKeyMaterial> getOrCreateKeyMaterial() async {
    if (!isSupportedOnCurrentPlatform) {
      throw StateError('ML-KEM is disabled on this platform.');
    }
    final cachedMaterial = _cachedMaterial;
    if (cachedMaterial != null) {
      return cachedMaterial;
    }
    final existingPublicKey = await _secretStore.read(_publicKeyKey);
    final existingSecretKey = await _secretStore.read(_secretKeyKey);
    final existingAlgorithm = await _secretStore.read(_algorithmKey);
    if (_isUsablePublicKey(existingPublicKey) &&
        _isUsableSecretKey(existingSecretKey) &&
        existingAlgorithm == algorithmName) {
      final material = DevicePqcKeyMaterial(
        publicKey: existingPublicKey!,
        secretKey: existingSecretKey!,
        algorithm: existingAlgorithm!,
      );
      _cachedMaterial = material;
      return material;
    }

    final (publicKey, secretKey) = _kem.generateKeyPair();
    final material = DevicePqcKeyMaterial(
      publicKey: base64Encode(publicKey),
      secretKey: base64Encode(secretKey),
      algorithm: algorithmName,
    );
    await _secretStore.write(key: _publicKeyKey, value: material.publicKey);
    await _secretStore.write(key: _secretKeyKey, value: material.secretKey);
    await _secretStore.write(key: _algorithmKey, value: material.algorithm);
    _cachedMaterial = material;
    return material;
  }

  Future<void> clearKeyMaterial() async {
    _cachedMaterial = null;
    await _secretStore.delete(_publicKeyKey);
    await _secretStore.delete(_secretKeyKey);
    await _secretStore.delete(_algorithmKey);
  }

  Future<Uint8List> decapsulate(String ciphertextBase64) async {
    final material = await getOrCreateKeyMaterial();
    final secretKey = base64Decode(material.secretKey);
    final ciphertext = base64Decode(ciphertextBase64);
    if (ciphertext.length != ciphertextLength) {
      throw ArgumentError('Invalid ML-KEM ciphertext length.');
    }
    return _kem.decapsulate(secretKey, ciphertext);
  }

  Future<(String ciphertext, Uint8List sharedSecret)> encapsulateForPublicKey(
    String publicKeyBase64,
  ) async {
    final publicKey = base64Decode(publicKeyBase64);
    if (publicKey.length != publicKeyLength) {
      throw ArgumentError('Invalid ML-KEM public key length.');
    }
    final (ciphertext, sharedSecret) = _kem.encapsulate(publicKey);
    return (base64Encode(ciphertext), sharedSecret);
  }

  bool isUsablePublicKey(String? publicKeyBase64) =>
      _isUsablePublicKey(publicKeyBase64);

  bool _isUsablePublicKey(String? publicKeyBase64) {
    if (publicKeyBase64 == null || publicKeyBase64.isEmpty) {
      return false;
    }
    try {
      return base64Decode(publicKeyBase64).length == publicKeyLength;
    } catch (_) {
      return false;
    }
  }

  bool _isUsableSecretKey(String? secretKeyBase64) {
    if (secretKeyBase64 == null || secretKeyBase64.isEmpty) {
      return false;
    }
    try {
      return base64Decode(secretKeyBase64).length == secretKeyLength;
    } catch (_) {
      return false;
    }
  }
}
