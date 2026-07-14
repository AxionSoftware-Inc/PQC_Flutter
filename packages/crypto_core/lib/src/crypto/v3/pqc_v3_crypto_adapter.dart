import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import 'v3_crypto_adapter.dart';

/// Production primitive adapter for v3. Wire serialization stays outside this
/// class; this class only owns KEM, signature and content AEAD operations.
class PqcV3CryptoAdapter implements V3CryptoAdapter {
  PqcV3CryptoAdapter({
    required this.keyService,
    required this.signingService,
    AesGcm? cipher,
  }) : _cipher = cipher ?? AesGcm.with256bits();

  final DevicePqcKeyService keyService;
  final DevicePqcSigningKeyService signingService;
  final AesGcm _cipher;

  @override
  Future<(String ciphertext, List<int> sharedSecret)> encapsulate(
    String recipientPublicKey,
  ) async {
    final result = await keyService.encapsulateForPublicKey(recipientPublicKey);
    return (result.$1, result.$2);
  }

  @override
  Future<List<int>> decapsulate(String ciphertext) async {
    return keyService.decapsulate(ciphertext);
  }

  @override
  Future<List<int>> decapsulateWithSecretKey({
    required String ciphertext,
    required String secretKey,
  }) {
    return keyService.decapsulateWithSecretKey(
      ciphertextBase64: ciphertext,
      secretKeyBase64: secretKey,
    );
  }

  @override
  Future<String> sign(List<int> message) {
    return signingService.sign(Uint8List.fromList(message));
  }

  @override
  bool verify({
    required String publicKey,
    required String signature,
    required List<int> message,
  }) {
    return signingService.verify(
      publicKeyBase64: publicKey,
      signatureBase64: signature,
      message: Uint8List.fromList(message),
    );
  }

  @override
  Future<List<int>> encrypt({
    required List<int> plaintext,
    required List<int> associatedData,
    required Map<String, dynamic> context,
  }) async {
    final key = context['content_key'];
    if (key is! List<int> || key.length != 32) {
      throw ArgumentError('v3 content_key must be exactly 32 bytes.');
    }
    final nonce = context['nonce'];
    if (nonce is! List<int> || nonce.length != 12) {
      throw ArgumentError('v3 nonce must be exactly 12 bytes.');
    }
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: associatedData,
    );
    return <int>[...box.nonce, ...box.cipherText, ...box.mac.bytes];
  }

  @override
  Future<List<int>> decrypt({
    required List<int> ciphertext,
    required List<int> associatedData,
    required Map<String, dynamic> context,
  }) async {
    final key = context['content_key'];
    if (key is! List<int> || key.length != 32) {
      throw ArgumentError('v3 content_key must be exactly 32 bytes.');
    }
    if (ciphertext.length < 12 + 16) {
      throw const FormatException('Invalid v3 ciphertext.');
    }
    final box = SecretBox(
      ciphertext.sublist(12, ciphertext.length - 16),
      nonce: ciphertext.sublist(0, 12),
      mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
    );
    return _cipher.decrypt(box, secretKey: SecretKey(key), aad: associatedData);
  }

  static List<int> associatedData({
    required int conversationId,
    required String conversationType,
    required String messageId,
    required String senderDeviceId,
    required String keysetId,
  }) {
    final canonical = jsonEncode({
      'conversation_id': conversationId,
      'conversation_type': conversationType,
      'message_id': messageId,
      'sender_device_id': senderDeviceId,
      'keyset_id': keysetId,
    });
    return utf8.encode(canonical);
  }
}
