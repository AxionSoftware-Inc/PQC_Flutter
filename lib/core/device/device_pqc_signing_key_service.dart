import 'dart:convert';
import 'dart:typed_data';

import 'package:pqcrypto/pqcrypto.dart';

import '../storage/local_secret_store.dart';

class DevicePqcSigningKeyMaterial {
  const DevicePqcSigningKeyMaterial({
    required this.publicKey,
    required this.secretKey,
    required this.algorithm,
  });

  final String publicKey;
  final String secretKey;
  final String algorithm;
}

class DevicePqcSigningKeyService {
  DevicePqcSigningKeyService({
    LocalSecretStore? secretStore,
    DilithiumParams? params,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _params = params ?? DilithiumParams.mlDsa65;

  static const algorithmName = 'ml-dsa-65';
  static const publicKeyLength = 1952;
  static const secretKeyLength = 4032;
  static const context = 'pqc-chat-device-sign-v1';

  static const _publicKeyKey = 'pqc_signing_public_key';
  static const _secretKeyKey = 'pqc_signing_secret_key';
  static const _algorithmKey = 'pqc_signing_algorithm';

  final LocalSecretStore _secretStore;
  final DilithiumParams _params;

  Future<DevicePqcSigningKeyMaterial> getOrCreateKeyMaterial() async {
    final existingPublicKey = await _secretStore.read(_publicKeyKey);
    final existingSecretKey = await _secretStore.read(_secretKeyKey);
    final existingAlgorithm = await _secretStore.read(_algorithmKey);
    if (_isUsablePublicKey(existingPublicKey) &&
        _isUsableSecretKey(existingSecretKey) &&
        existingAlgorithm == algorithmName) {
      return DevicePqcSigningKeyMaterial(
        publicKey: existingPublicKey!,
        secretKey: existingSecretKey!,
        algorithm: existingAlgorithm!,
      );
    }

    final (publicKey, secretKey) = MlDsa.generateKeyPair(_params);
    final material = DevicePqcSigningKeyMaterial(
      publicKey: base64Encode(publicKey),
      secretKey: base64Encode(secretKey),
      algorithm: algorithmName,
    );
    await _secretStore.write(key: _publicKeyKey, value: material.publicKey);
    await _secretStore.write(key: _secretKeyKey, value: material.secretKey);
    await _secretStore.write(key: _algorithmKey, value: material.algorithm);
    return material;
  }

  Future<String> sign(Uint8List message) async {
    final material = await getOrCreateKeyMaterial();
    final secretKey = base64Decode(material.secretKey);
    final signature = MlDsa.sign(
      secretKey,
      message,
      _params,
      ctx: Uint8List.fromList(context.codeUnits),
    );
    return base64Encode(signature);
  }

  bool verify({
    required String publicKeyBase64,
    required String signatureBase64,
    required Uint8List message,
  }) {
    try {
      final publicKey = base64Decode(publicKeyBase64);
      final signature = base64Decode(signatureBase64);
      return MlDsa.verify(
        publicKey,
        message,
        signature,
        _params,
        ctx: Uint8List.fromList(context.codeUnits),
      );
    } catch (_) {
      return false;
    }
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
