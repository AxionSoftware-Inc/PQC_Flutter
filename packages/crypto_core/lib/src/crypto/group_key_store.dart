// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'package:crypto_core/src/core/device/device_identity_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_key_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_signing_key_service.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'package:crypto_core/src/models/conversation_key_envelope.dart';
import 'package:crypto_core/src/core/storage/local_secret_store.dart';
import 'package:crypto_core/src/support/conversation_device_policy.dart';
import 'package:crypto_core/src/support/chat_models.dart';
import 'chat_crypto_exceptions.dart';

class GroupKeyMaterial {
  const GroupKeyMaterial({required this.keyId, required this.secretKeyBytes});

  final String keyId;
  final List<int> secretKeyBytes;
}

abstract class GroupKeyProvider {
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  });

  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  });
}

abstract interface class ConversationKeyEnvelopeGateway {
  Future<void> syncConversationKeyEnvelopes({
    required int conversationId,
    required String keyId,
    required String algorithm,
    required List<ConversationKeyEnvelopeUpload> envelopes,
  });

  Future<List<ConversationKeyEnvelope>> fetchConversationKeyEnvelopes(
    int conversationId,
  );
}

class GroupKeyStore implements GroupKeyProvider {
  GroupKeyStore({
    required DeviceIdentityService deviceIdentityService,
    required DevicePqcKeyService devicePqcKeyService,
    required DevicePqcSigningKeyService devicePqcSigningKeyService,
    required ConversationKeyEnvelopeGateway remoteDataSource,
    ConversationDevicePolicy? devicePolicy,
    LocalSecretStore? secretStore,
    Hkdf? hkdf,
    AesGcm? cipher,
    Uuid? uuid,
  }) : _deviceIdentityService = deviceIdentityService,
       _devicePqcKeyService = devicePqcKeyService,
       _devicePqcSigningKeyService = devicePqcSigningKeyService,
       _remoteDataSource = remoteDataSource,
       _devicePolicy = devicePolicy ?? const ConversationDevicePolicy(),
       _secretStore = secretStore ?? LocalSecretStore(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _cipher = cipher ?? AesGcm.with256bits(),
       _uuid = uuid ?? const Uuid();

  static const _localKeyPrefix = 'group_secret_key';
  static const _participantSignaturePrefix = 'group_participant_signature';
  static const _wrapPrefix = 'group-wrap:pqc:v1';
  static final _random = Random.secure();

  final DeviceIdentityService _deviceIdentityService;
  final DevicePqcKeyService _devicePqcKeyService;
  final DevicePqcSigningKeyService _devicePqcSigningKeyService;
  final ConversationKeyEnvelopeGateway _remoteDataSource;
  final ConversationDevicePolicy _devicePolicy;
  final LocalSecretStore _secretStore;
  final Hkdf _hkdf;
  final AesGcm _cipher;
  final Uuid _uuid;

  @override
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    final targetDevices = _resolveTargetDevices(
      conversation: conversation,
      usersById: usersById,
    );
    final currentSignature = _participantSignature(
      conversation: conversation,
      usersById: usersById,
    );
    final existing = await getExistingKey(
      conversation: conversation,
      usersById: usersById,
    );
    final savedSignature = await _secretStore.read(
      _participantSignatureStorageKey(conversation.id),
    );
    if (existing != null && savedSignature == currentSignature) {
      return existing;
    }

    final deviceIdentity = await _deviceIdentityService.getIdentity();
    final keyId = _uuid.v4();
    final secretKeyBytes = List<int>.generate(32, (_) => _random.nextInt(256));
    final envelopes = <ConversationKeyEnvelopeUpload>[];

    for (final device in targetDevices) {
      envelopes.add(
        ConversationKeyEnvelopeUpload(
          targetDeviceId: device.deviceId,
          wrappedKey: await _wrapGroupKeyForDevice(
            conversation: conversation,
            keyId: keyId,
            senderDeviceId: deviceIdentity.id,
            targetDevice: device,
            secretKeyBytes: secretKeyBytes,
          ),
        ),
      );
    }

    if (envelopes.length != targetDevices.length) {
      throw ChatEncryptionException(
        'Group key distribution incomplete. Retry after all participants re-open the app.',
      );
    }

    await _remoteDataSource.syncConversationKeyEnvelopes(
      conversationId: conversation.id,
      keyId: keyId,
      algorithm: 'group-ml-kem-768-aesgcm-v1',
      envelopes: envelopes,
    );
    await _saveLocalKey(
      conversationId: conversation.id,
      keyId: keyId,
      secretKeyBytes: secretKeyBytes,
    );
    await _secretStore.write(
      key: _participantSignatureStorageKey(conversation.id),
      value: currentSignature,
    );

    return GroupKeyMaterial(keyId: keyId, secretKeyBytes: secretKeyBytes);
  }

  @override
  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  }) async {
    if (requestedKeyId != null) {
      final cached = await _readLocalKey(
        conversationId: conversation.id,
        keyId: requestedKeyId,
      );
      if (cached != null) {
        return GroupKeyMaterial(keyId: requestedKeyId, secretKeyBytes: cached);
      }
    }
    final deviceIdentity = await _deviceIdentityService.getIdentity();
    final envelopes = await _remoteDataSource.fetchConversationKeyEnvelopes(
      conversation.id,
    );
    final relevantEnvelopes = envelopes.where((item) {
      if (item.targetDeviceId != deviceIdentity.id) {
        return false;
      }
      if (requestedKeyId == null) {
        return true;
      }
      return item.keyId == requestedKeyId;
    }).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    for (final envelope in relevantEnvelopes) {
      final cached = await _readLocalKey(
        conversationId: conversation.id,
        keyId: envelope.keyId,
      );
      if (cached != null) {
        return GroupKeyMaterial(keyId: envelope.keyId, secretKeyBytes: cached);
      }

      final senderDevice = _findDeviceById(
        usersById: usersById,
        deviceId: envelope.senderDeviceId,
      );
      if (senderDevice == null) {
        continue;
      }
      final secretKeyBytes = await _unwrapGroupKeyFromEnvelope(
        conversation: conversation,
        keyId: envelope.keyId,
        senderDevice: senderDevice,
        targetDeviceId: envelope.targetDeviceId,
        wrappedKey: envelope.wrappedKey,
      );
      if (secretKeyBytes == null) {
        continue;
      }

      await _saveLocalKey(
        conversationId: conversation.id,
        keyId: envelope.keyId,
        secretKeyBytes: secretKeyBytes,
      );
      return GroupKeyMaterial(
        keyId: envelope.keyId,
        secretKeyBytes: secretKeyBytes,
      );
    }

    return null;
  }

  AppUserDevice? _findDeviceById({
    required Map<int, AppUser> usersById,
    required String deviceId,
  }) {
    return _devicePolicy.findDeviceById(
      usersById: usersById,
      deviceId: deviceId,
    );
  }

  Future<String> _wrapGroupKeyForDevice({
    required Conversation conversation,
    required String keyId,
    required String senderDeviceId,
    required AppUserDevice targetDevice,
    required List<int> secretKeyBytes,
  }) async {
    final localSigningMaterial = await _devicePqcSigningKeyService
        .getOrCreateKeyMaterial();
    final (kemCiphertext, sharedSecret) = await _devicePqcKeyService
        .encapsulateForPublicKey(targetDevice.pqcPublicKey);
    final wrappingKey = await _deriveWrappingKey(
      sharedSecret: sharedSecret,
      info:
          '${conversation.id}|$keyId|$senderDeviceId|${targetDevice.deviceId}',
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      secretKeyBytes,
      secretKey: wrappingKey,
      nonce: nonce,
    );
    final payloadParts = [
      senderDeviceId,
      localSigningMaterial.publicKey,
      kemCiphertext,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ];
    final signature = await _devicePqcSigningKeyService.sign(
      Uint8List.fromList(([_wrapPrefix, ...payloadParts]).join(':').codeUnits),
    );
    return [_wrapPrefix, ...payloadParts, signature].join(':');
  }

  Future<List<int>?> _unwrapGroupKeyFromEnvelope({
    required Conversation conversation,
    required String keyId,
    required AppUserDevice senderDevice,
    required String targetDeviceId,
    required String wrappedKey,
  }) async {
    try {
      if (!wrappedKey.startsWith('$_wrapPrefix:')) {
        return null;
      }

      final parts = wrappedKey.substring(_wrapPrefix.length + 1).split(':');
      if (parts.length != 7) {
        return null;
      }
      final senderDeviceId = parts[0];
      final signingPublicKey = parts[1];
      final kemCiphertext = parts[2];
      final signature = parts[6];
      if (senderDevice.deviceId != senderDeviceId ||
          !senderDevice.hasUsableMlDsaKey ||
          senderDevice.pqcSigningPublicKey != signingPublicKey) {
        return null;
      }
      final verified = _devicePqcSigningKeyService.verify(
        publicKeyBase64: signingPublicKey,
        signatureBase64: signature,
        message: Uint8List.fromList(
          ([_wrapPrefix, ...parts.sublist(0, 6)]).join(':').codeUnits,
        ),
      );
      if (!verified) {
        return null;
      }
      final sharedSecret = await _devicePqcKeyService.decapsulate(
        kemCiphertext,
      );
      final wrappingKey = await _deriveWrappingKey(
        sharedSecret: sharedSecret,
        info:
            '${conversation.id}|$keyId|${senderDevice.deviceId}|$targetDeviceId',
      );
      final secretBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[4]),
          nonce: base64Decode(parts[3]),
          mac: Mac(base64Decode(parts[5])),
        ),
        secretKey: wrappingKey,
      );
      return secretBytes;
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveWrappingKey({
    required Uint8List sharedSecret,
    required String info,
  }) async {
    return _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecret),
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-group-key-wrap-v1'),
    );
  }

  Future<void> _saveLocalKey({
    required int conversationId,
    required String keyId,
    required List<int> secretKeyBytes,
  }) {
    return _secretStore.write(
      key: _localStorageKey(conversationId: conversationId, keyId: keyId),
      value: base64Encode(secretKeyBytes),
    );
  }

  Future<List<int>?> _readLocalKey({
    required int conversationId,
    required String keyId,
  }) async {
    final value = await _secretStore.read(
      _localStorageKey(conversationId: conversationId, keyId: keyId),
    );
    if (value == null || value.isEmpty) {
      return null;
    }
    return base64Decode(value);
  }

  String _localStorageKey({
    required int conversationId,
    required String keyId,
  }) {
    return '${_localKeyPrefix}_${conversationId}_$keyId';
  }

  String _participantSignatureStorageKey(int conversationId) {
    return '${_participantSignaturePrefix}_$conversationId';
  }

  String _participantSignature({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    return _devicePolicy.buildParticipantSignature(
      conversation: conversation,
      usersById: usersById,
    );
  }

  List<AppUserDevice> _resolveTargetDevices({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final resolution = _devicePolicy.resolveGroupTargetDevices(
      conversation: conversation,
      usersById: usersById,
    );
    if (resolution.issue == DeviceResolutionIssue.missingParticipants) {
      throw ChatEncryptionException(
        'Group chat ready emas. Key yoq participantlar: ${resolution.missingParticipants.join(", ")}.',
      );
    }
    if (!resolution.isReady) {
      throw ChatEncryptionException('Groupda usable device key topilmadi.');
    }
    return resolution.devices;
  }
}
