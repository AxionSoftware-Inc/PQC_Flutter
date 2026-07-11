import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/device/device_identity_service.dart';
import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';
import '../chat/application/conversation_device_policy.dart';
import 'chat_crypto_exceptions.dart';
import 'group_key_store.dart';

class PqcPrivateMessageCodec {
  PqcPrivateMessageCodec({
    required this.deviceIdentityService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    ConversationDevicePolicy? devicePolicy,
    AesGcm? cipher,
    Hkdf? hkdf,
  }) : _cipher = cipher ?? AesGcm.with256bits(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _devicePolicy = devicePolicy ?? const ConversationDevicePolicy();

  static const prefix = 'pqc:v1';
  static final _random = Random.secure();

  final DeviceIdentityService deviceIdentityService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final ConversationDevicePolicy _devicePolicy;
  final AesGcm _cipher;
  final Hkdf _hkdf;

  Future<String> encrypt({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final peerDevice = _resolvePeerPqcDevice(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    final localIdentity = await deviceIdentityService.getIdentity();
    final localPqcKeyMaterial = await devicePqcKeyService
        .getOrCreateKeyMaterial();
    final localSigningKeyMaterial = await devicePqcSigningKeyService
        .getOrCreateKeyMaterial();
    final contentKeyBytes = List<int>.generate(
      DevicePqcKeyService.sharedSecretLength,
      (_) => _random.nextInt(256),
    );
    final contentNonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final contentBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(contentKeyBytes),
      nonce: contentNonce,
    );
    final selfWrap = await _wrapContentKeyForDevice(
      publicKeyBase64: localPqcKeyMaterial.publicKey,
      senderDeviceId: localIdentity.id,
      targetDeviceId: localIdentity.id,
      conversation: conversation,
      contentKeyBytes: contentKeyBytes,
    );
    final peerWrap = await _wrapContentKeyForDevice(
      publicKeyBase64: peerDevice.pqcPublicKey,
      senderDeviceId: localIdentity.id,
      targetDeviceId: peerDevice.deviceId,
      conversation: conversation,
      contentKeyBytes: contentKeyBytes,
    );
    final payloadParts = [
      localIdentity.id,
      localSigningKeyMaterial.publicKey,
      peerDevice.deviceId,
      selfWrap.kemCiphertext,
      base64Encode(selfWrap.nonce),
      base64Encode(selfWrap.cipherText),
      base64Encode(selfWrap.macBytes),
      peerWrap.kemCiphertext,
      base64Encode(peerWrap.nonce),
      base64Encode(peerWrap.cipherText),
      base64Encode(peerWrap.macBytes),
      base64Encode(contentBox.nonce),
      base64Encode(contentBox.cipherText),
      base64Encode(contentBox.mac.bytes),
    ];
    final signature = await devicePqcSigningKeyService.sign(
      Uint8List.fromList(([prefix, ...payloadParts]).join(':').codeUnits),
    );
    return [prefix, ...payloadParts, signature].join(':');
  }

  Future<String> decrypt({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    if (!payload.startsWith('$prefix:')) {
      return payload;
    }

    try {
      final parts = payload.substring(prefix.length + 1).split(':');
      if (parts.length != 15) {
        return '[decrypt-error]';
      }
      final senderDeviceId = parts[0];
      final signingPublicKey = parts[1];
      final targetDeviceId = parts[2];
      final signature = parts[14];
      if (!_verifySenderSignature(
        currentUserId: currentUserId,
        usersById: usersById,
        senderDeviceId: senderDeviceId,
        signingPublicKey: signingPublicKey,
        payloadParts: parts.sublist(0, 14),
        signature: signature,
      )) {
        return '[decrypt-error]';
      }
      final localIdentity = await deviceIdentityService.getIdentity();
      late final _WrappedContentKeyEnvelope wrap;
      if (localIdentity.id == senderDeviceId) {
        wrap = _WrappedContentKeyEnvelope(
          kemCiphertext: parts[3],
          nonce: base64Decode(parts[4]),
          cipherText: base64Decode(parts[5]),
          macBytes: base64Decode(parts[6]),
        );
      } else if (localIdentity.id == targetDeviceId) {
        wrap = _WrappedContentKeyEnvelope(
          kemCiphertext: parts[7],
          nonce: base64Decode(parts[8]),
          cipherText: base64Decode(parts[9]),
          macBytes: base64Decode(parts[10]),
        );
      } else {
        return '[decrypt-error]';
      }
      final contentKeyBytes = await _unwrapContentKeyForCurrentDevice(
        senderDeviceId: senderDeviceId,
        localDeviceId: localIdentity.id,
        conversation: conversation,
        wrap: wrap,
      );
      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[12]),
          nonce: base64Decode(parts[11]),
          mac: Mac(base64Decode(parts[13])),
        ),
        secretKey: SecretKey(contentKeyBytes),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '[decrypt-error]';
    }
  }

  Future<_WrappedContentKeyEnvelope> _wrapContentKeyForDevice({
    required String publicKeyBase64,
    required String senderDeviceId,
    required String targetDeviceId,
    required Conversation conversation,
    required List<int> contentKeyBytes,
  }) async {
    final (kemCiphertext, sharedSecret) = await devicePqcKeyService
        .encapsulateForPublicKey(publicKeyBase64);
    final wrapKey = await _deriveWrapKey(
      sharedSecret: sharedSecret,
      conversation: conversation,
      senderDeviceId: senderDeviceId,
      targetDeviceId: targetDeviceId,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final wrappedBox = await _cipher.encrypt(
      contentKeyBytes,
      secretKey: wrapKey,
      nonce: nonce,
    );
    return _WrappedContentKeyEnvelope(
      kemCiphertext: kemCiphertext,
      nonce: wrappedBox.nonce,
      cipherText: wrappedBox.cipherText,
      macBytes: wrappedBox.mac.bytes,
    );
  }

  Future<List<int>> _unwrapContentKeyForCurrentDevice({
    required String senderDeviceId,
    required String localDeviceId,
    required Conversation conversation,
    required _WrappedContentKeyEnvelope wrap,
  }) async {
    final sharedSecret = await devicePqcKeyService.decapsulate(
      wrap.kemCiphertext,
    );
    final wrapKey = await _deriveWrapKey(
      sharedSecret: sharedSecret,
      conversation: conversation,
      senderDeviceId: senderDeviceId,
      targetDeviceId: localDeviceId,
    );
    return _cipher.decrypt(
      SecretBox(wrap.cipherText, nonce: wrap.nonce, mac: Mac(wrap.macBytes)),
      secretKey: wrapKey,
    );
  }

  Future<SecretKey> _deriveWrapKey({
    required Uint8List sharedSecret,
    required Conversation conversation,
    required String senderDeviceId,
    required String targetDeviceId,
  }) {
    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: utf8.encode(
        '${conversation.id}|${conversation.type}|$senderDeviceId|$targetDeviceId',
      ),
      info: utf8.encode('pqc-chat-private-wrap-v1'),
    );
  }

  bool _verifySenderSignature({
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String senderDeviceId,
    required String signingPublicKey,
    required List<String> payloadParts,
    required String signature,
  }) {
    final senderDevice = _findPeerDeviceById(
      currentUserId: currentUserId,
      usersById: usersById,
      deviceId: senderDeviceId,
    );
    if (senderDevice != null &&
        senderDevice.hasUsableMlDsaKey &&
        senderDevice.pqcSigningPublicKey != signingPublicKey) {
      return false;
    }
    return devicePqcSigningKeyService.verify(
      publicKeyBase64: signingPublicKey,
      signatureBase64: signature,
      message: Uint8List.fromList(
        ([prefix, ...payloadParts]).join(':').codeUnits,
      ),
    );
  }

  AppUserDevice _resolvePeerPqcDevice({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final resolution = _devicePolicy.resolvePrivatePeerPqcDevice(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    if (!resolution.isReady || resolution.device == null) {
      throw ChatEncryptionException(
        'Peer PQC device key is not ready yet. Ask them to reopen the app.',
      );
    }
    return resolution.device!;
  }

  AppUserDevice? _findPeerDeviceById({
    required int currentUserId,
    required Map<int, AppUser> usersById,
    required String deviceId,
  }) {
    return _devicePolicy.findDeviceById(
      usersById: usersById,
      deviceId: deviceId,
      excludeUserId: currentUserId,
    );
  }
}

class GroupCipherMessageCodec {
  GroupCipherMessageCodec({required this._groupKeyStore, AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static const prefix = 'group:v1';
  static final _random = Random.secure();

  final GroupKeyProvider _groupKeyStore;
  final AesGcm _cipher;

  Future<String> encrypt({
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final keyMaterial = await _groupKeyStore.getOrCreateKey(
      conversation: conversation,
      usersById: usersById,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyMaterial.secretKeyBytes),
      nonce: nonce,
    );

    return [
      prefix,
      keyMaterial.keyId,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      final parts = payload.substring(prefix.length + 1).split(':');
      if (parts.length != 4) {
        return '[decrypt-error]';
      }

      final keyMaterial = await _groupKeyStore.getExistingKey(
        conversation: conversation,
        usersById: usersById,
        requestedKeyId: parts[0],
      );
      if (keyMaterial == null) {
        return '[decrypt-error]';
      }

      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[2]),
          nonce: base64Decode(parts[1]),
          mac: Mac(base64Decode(parts[3])),
        ),
        secretKey: SecretKey(keyMaterial.secretKeyBytes),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '[decrypt-error]';
    }
  }
}

class _WrappedContentKeyEnvelope {
  const _WrappedContentKeyEnvelope({
    required this.kemCiphertext,
    required this.nonce,
    required this.cipherText,
    required this.macBytes,
  });

  final String kemCiphertext;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> macBytes;
}
