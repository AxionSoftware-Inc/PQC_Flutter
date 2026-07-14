import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'package:crypto_core/src/core/device/device_identity_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_key_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_signing_key_service.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'package:crypto_core/src/support/conversation_device_policy.dart';
import 'durability/key_material_registry.dart';
import 'chat_crypto_exceptions.dart';
import 'group_key_store.dart';
import 'durability/v2_protocol_contract.dart';

class PqcPrivateMessageCodec {
  PqcPrivateMessageCodec({
    required this.deviceIdentityService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    KeyMaterialRegistry? keyMaterialRegistry,
    ConversationDevicePolicy? devicePolicy,
    AesGcm? cipher,
    Hkdf? hkdf,
  }) : _cipher = cipher ?? AesGcm.with256bits(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _devicePolicy = devicePolicy ?? const ConversationDevicePolicy(),
       _keyMaterialRegistry =
           keyMaterialRegistry ??
           KeyMaterialRegistry(
             devicePqcKeyService: devicePqcKeyService,
             devicePqcSigningKeyService: devicePqcSigningKeyService,
           );

  /// PQCv2 is an immutable, explicit-keyset wire format.  PQCv1 deliberately
  /// has no reader here: it was a beta protocol with no recovery guarantee.
  static const prefix = PqcV2ProtocolContract.privatePrefix;
  static final _random = Random.secure();

  final DeviceIdentityService deviceIdentityService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final ConversationDevicePolicy _devicePolicy;
  final KeyMaterialRegistry _keyMaterialRegistry;
  final AesGcm _cipher;
  final Hkdf _hkdf;

  Future<String> encrypt({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
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
    final targetDevices = _resolvePrivateTargetDevices(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
      localDeviceId: localIdentity.id,
      localPqcPublicKey: localPqcKeyMaterial.publicKey,
    );
    final wraps = <Map<String, String>>[];
    for (final device in targetDevices) {
      final wrap = await _wrapContentKeyForDevice(
        publicKeyBase64: device.pqcPublicKey,
        senderDeviceId: localIdentity.id,
        targetDeviceId: device.deviceId,
        conversation: conversation,
        contentKeyBytes: contentKeyBytes,
      );
      wraps.add({
        'target_device_id': device.deviceId,
        'target_keyset_id': _keysetId(device.deviceId, device.pqcPublicKey),
        'kem_ciphertext': wrap.kemCiphertext,
        'nonce': base64Encode(wrap.nonce),
        'ciphertext': base64Encode(wrap.cipherText),
        'mac': base64Encode(wrap.macBytes),
      });
    }
    final unsigned = <String, dynamic>{
      'protocol_version': PqcV2ProtocolContract.protocolVersion,
      'algorithm': PqcV2ProtocolContract.privateAlgorithm,
      'conversation_id': conversation.id,
      'conversation_type': conversation.type,
      'sender_device_id': localIdentity.id,
      'sender_keyset_id': _keysetId(
        localIdentity.id,
        localPqcKeyMaterial.publicKey,
      ),
      'signing_public_key': localSigningKeyMaterial.publicKey,
      'content_nonce': base64Encode(contentBox.nonce),
      'content_ciphertext': base64Encode(contentBox.cipherText),
      'content_mac': base64Encode(contentBox.mac.bytes),
      'wraps': wraps,
    };
    final signature = await devicePqcSigningKeyService.sign(
      Uint8List.fromList(utf8.encode(jsonEncode(unsigned))),
    );
    final encodedDocument = base64UrlEncode(
      utf8.encode(jsonEncode({...unsigned, 'signature': signature})),
    ).replaceAll('=', '');
    return '$prefix:$encodedDocument';
  }

  Future<String> decrypt({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      if (!payload.startsWith('$prefix:')) return '[history-unavailable]';
      final encoded = payload.substring(prefix.length + 1);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final document =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
      if (document['protocol_version'] !=
              PqcV2ProtocolContract.protocolVersion ||
          document['algorithm'] != PqcV2ProtocolContract.privateAlgorithm ||
          document['conversation_id'] != conversation.id ||
          document['conversation_type'] != conversation.type) {
        return '[decrypt-error]';
      }
      final signature = document.remove('signature') as String?;
      final senderDeviceId = document['sender_device_id'] as String? ?? '';
      final signingPublicKey = document['signing_public_key'] as String? ?? '';
      if (!_verifySenderSignature(
        usersById: usersById,
        senderDeviceId: senderDeviceId,
        signingPublicKey: signingPublicKey,
        unsignedDocument: document,
        signature: signature ?? '',
      )) {
        return '[decrypt-error]';
      }
      final localIdentity = await deviceIdentityService.getIdentity();
      final wraps = (document['wraps'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', '$value')))
          .toList();
      final current = await devicePqcKeyService.getOrCreateKeyMaterial();
      Map<String, String>? selected = wraps
          .where(
            (item) =>
                item['target_device_id'] == localIdentity.id &&
                item['target_keyset_id'] ==
                    _keysetId(localIdentity.id, current.publicKey),
          )
          .cast<Map<String, String>?>()
          .firstWhere((item) => item != null, orElse: () => null);
      String secretKey = current.secretKey;
      String targetDeviceId = localIdentity.id;
      if (selected == null) {
        for (final candidate in wraps) {
          final keyset = await _keyMaterialRegistry.readKeyset(
            candidate['target_keyset_id'] ?? '',
          );
          if (keyset != null &&
              keyset.isHistoricalReadEnabled &&
              keyset.deviceId == candidate['target_device_id']) {
            selected = candidate;
            secretKey = keyset.pqcSecretKey;
            targetDeviceId = keyset.deviceId;
            break;
          }
        }
      }
      if (selected == null) return '[history-recovery-pending]';
      final wrap = _WrappedContentKeyEnvelope(
        kemCiphertext: selected['kem_ciphertext']!,
        nonce: base64Decode(selected['nonce']!),
        cipherText: base64Decode(selected['ciphertext']!),
        macBytes: base64Decode(selected['mac']!),
      );
      final contentKeyBytes = await _unwrapContentKeyForCurrentDevice(
        senderDeviceId: senderDeviceId,
        localDeviceId: targetDeviceId,
        conversation: conversation,
        wrap: wrap,
        secretKeyBase64: secretKey,
      );
      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(document['content_ciphertext'] as String),
          nonce: base64Decode(document['content_nonce'] as String),
          mac: Mac(base64Decode(document['content_mac'] as String)),
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
    required String secretKeyBase64,
  }) async {
    final sharedSecret = await devicePqcKeyService.decapsulateWithSecretKey(
      ciphertextBase64: wrap.kemCiphertext,
      secretKeyBase64: secretKeyBase64,
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
    required Map<int, AppUser> usersById,
    required String senderDeviceId,
    required String signingPublicKey,
    required Map<String, dynamic> unsignedDocument,
    required String signature,
  }) {
    final senderDevice = _findPeerDeviceById(
      usersById: usersById,
      deviceId: senderDeviceId,
    );
    if (senderDevice != null &&
        senderDevice.hasUsableMlDsaKey &&
        senderDevice.pqcSigningPublicKey != signingPublicKey) {
      // A device id may have rotated keys. Historical public keys are kept
      // alongside the active record and remain valid for old signatures.
      return false;
    }
    return devicePqcSigningKeyService.verify(
      publicKeyBase64: signingPublicKey,
      signatureBase64: signature,
      message: Uint8List.fromList(utf8.encode(jsonEncode(unsignedDocument))),
    );
  }

  List<AppUserDevice> _resolvePrivateTargetDevices({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required String localDeviceId,
    required String localPqcPublicKey,
  }) {
    final devices = <AppUserDevice>[];
    for (final participantId in conversation.participantIds) {
      final user = usersById[participantId];
      if (user == null) continue;
      devices.addAll(
        user.devices.where(
          (device) => device.isActive && device.hasUsableMlKemKey,
        ),
      );
    }
    if (!devices.any((item) => item.deviceId == localDeviceId)) {
      devices.add(
        AppUserDevice(
          deviceId: localDeviceId,
          deviceName: '',
          platform: '',
          identityPublicKey: '',
          keyAlgorithm: '',
          pqcPublicKey: localPqcPublicKey,
          pqcAlgorithm: DevicePqcKeyService.algorithmName,
          pqcSigningPublicKey: '',
          pqcSigningAlgorithm: '',
        ),
      );
    }
    final unique = <String, AppUserDevice>{
      for (final item in devices) item.deviceId: item,
    };
    if (unique.length < 2 && conversation.participantIds.length > 1) {
      throw ChatEncryptionException(
        'All active private-chat participant devices need ML-KEM keys.',
      );
    }
    return unique.values.toList();
  }

  AppUserDevice? _findPeerDeviceById({
    required Map<int, AppUser> usersById,
    required String deviceId,
  }) {
    return _devicePolicy.findDeviceById(
      usersById: usersById,
      deviceId: deviceId,
      includeHistorical: true,
    );
  }

  String _keysetId(String deviceId, String pqcPublicKey) {
    final bytes = crypto.sha256
        .convert(utf8.encode('$deviceId|$pqcPublicKey'))
        .bytes;
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}

class GroupCipherMessageCodec {
  GroupCipherMessageCodec({required this._groupKeyStore, AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static const prefix = PqcV2ProtocolContract.groupPrefix;
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

    final document = <String, dynamic>{
      'protocol_version': PqcV2ProtocolContract.protocolVersion,
      'algorithm': PqcV2ProtocolContract.groupAlgorithm,
      'conversation_id': conversation.id,
      'conversation_type': conversation.type,
      'group_epoch_id': keyMaterial.keyId,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    final encodedDocument = base64UrlEncode(
      utf8.encode(jsonEncode(document)),
    ).replaceAll('=', '');
    return '$prefix:$encodedDocument';
  }

  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      if (!payload.startsWith('$prefix:')) return '[history-unavailable]';
      final encoded = payload.substring(prefix.length + 1);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final document =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
      if (document['protocol_version'] !=
              PqcV2ProtocolContract.protocolVersion ||
          document['algorithm'] != PqcV2ProtocolContract.groupAlgorithm ||
          document['conversation_id'] != conversation.id ||
          document['conversation_type'] != conversation.type) {
        return '[decrypt-error]';
      }

      final keyMaterial = await _groupKeyStore.getExistingKey(
        conversation: conversation,
        usersById: usersById,
        requestedKeyId: document['group_epoch_id'] as String?,
      );
      if (keyMaterial == null) {
        return '[decrypt-error]';
      }

      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(document['ciphertext'] as String),
          nonce: base64Decode(document['nonce'] as String),
          mac: Mac(base64Decode(document['mac'] as String)),
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
