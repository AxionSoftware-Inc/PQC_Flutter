// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;
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
import 'durability/payload_format_registry.dart';
import 'durability/v2_protocol_contract.dart';

class GroupKeyMaterial {
  const GroupKeyMaterial({required this.keyId, required this.secretKeyBytes});

  final String keyId;
  final List<int> secretKeyBytes;
}

enum GroupEnvelopeWriter { v2, v25 }

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
  static const _wrapPrefix = PqcV2ProtocolContract.groupWrapPrefix;
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
  GroupEnvelopeWriter _groupEnvelopeWriter = GroupEnvelopeWriter.v2;

  /// Negotiates the group-key envelope independently from message payloads.
  /// V2 remains the safe default; V2.5 is selected only when the server has
  /// advertised both read and write support for the new envelope prefix.
  void configureGroupEnvelopeWriter({
    required Iterable<String> readablePrefixes,
    required Iterable<String> writablePrefixes,
    PayloadWriteProfile writeProfile = PayloadWriteProfile.v2,
  }) {
    final readable = readablePrefixes.map(_withoutTrailingColon).toSet();
    final writable = writablePrefixes.map(_withoutTrailingColon).toSet();
    _groupEnvelopeWriter =
        writeProfile == PayloadWriteProfile.v25 &&
            readable.contains(sdk.PqcV2Wire.groupWrapV25Prefix) &&
            writable.contains(sdk.PqcV2Wire.groupWrapV25Prefix)
        ? GroupEnvelopeWriter.v25
        : GroupEnvelopeWriter.v2;
  }

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
    final coveredUserIds = <int>{};
    final malformedDeviceIds = <String>[];

    for (final device in targetDevices) {
      try {
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
        final userId = _userIdForDevice(usersById, device.deviceId);
        if (userId != null) {
          coveredUserIds.add(userId);
        }
      } on ArgumentError {
        // A legacy/server-corrupted ML-KEM key can have the expected byte
        // length yet still fail polynomial decoding.  It is not a usable
        // active device and must not prevent every healthy group member from
        // receiving a new epoch.
        malformedDeviceIds.add(device.deviceId);
      }
    }

    // The local sender receives this freshly generated epoch directly through
    // protected storage; it does not need a self-envelope to be covered.
    final coveredParticipants = {
      ...coveredUserIds,
      _userIdForDevice(usersById, deviceIdentity.id),
    }..remove(null);
    final missingParticipants = conversation.participantIds
        .where((userId) => !coveredParticipants.contains(userId))
        .map((userId) => usersById[userId]?.displayName ?? 'user-$userId')
        .toList();
    if (missingParticipants.isNotEmpty) {
      throw ChatEncryptionException(
        'Group key yangilanishi kerak: ${missingParticipants.join(', ')}. '
        'Ular ilovani qayta ochib, device keyni yangilashi kerak.',
      );
    }

    await _remoteDataSource.syncConversationKeyEnvelopes(
      conversationId: conversation.id,
      keyId: keyId,
      algorithm: _groupEnvelopeWriter == GroupEnvelopeWriter.v25
          ? sdk.PqcV2Wire.groupEnvelopeV25Algorithm
          : PqcV2ProtocolContract.groupEnvelopeAlgorithm,
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
        algorithm: envelope.algorithm,
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
      includeHistorical: true,
    );
  }

  int? _userIdForDevice(Map<int, AppUser> usersById, String deviceId) {
    for (final entry in usersById.entries) {
      if (entry.value.devices.any((item) => item.deviceId == deviceId)) {
        return entry.key;
      }
    }
    return null;
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

  Future<String> _wrapGroupKeyForDevice({
    required Conversation conversation,
    required String keyId,
    required String senderDeviceId,
    required AppUserDevice targetDevice,
    required List<int> secretKeyBytes,
  }) async {
    if (_groupEnvelopeWriter == GroupEnvelopeWriter.v25) {
      if (!targetDevice.supportsProtocol('v2.5')) {
        throw ArgumentError(
          'Target device does not advertise V2.5 group-envelope support.',
        );
      }
      final localPqc = await _devicePqcKeyService.getOrCreateKeyMaterial();
      final localSigning = await _devicePqcSigningKeyService
          .getOrCreateKeyMaterial();
      final targetBindingId = targetDevice.v3KeysetId;
      if (targetBindingId.isEmpty || !targetDevice.hasUsableMlDsaKey) {
        throw ArgumentError('Target device has no valid V2.5 keyset binding.');
      }
      return sdk.PqcV25GroupEpochCodec(sdk.DartPqcPrimitiveSuite()).wrapEpoch(
        conversation: sdk.PqcConversation(
          id: conversation.id,
          type: conversation.type,
        ),
        epoch: sdk.PqcGroupEpoch(
          epochId: keyId,
          secretKeyBytes: secretKeyBytes,
        ),
        sender: sdk.PqcDeviceKeyset(
          deviceId: senderDeviceId,
          kemPublicKeyBase64: localPqc.publicKey,
          kemSecretKeyBase64: localPqc.secretKey,
          signingPublicKeyBase64: localSigning.publicKey,
          signingSecretKeyBase64: localSigning.secretKey,
        ),
        recipient: sdk.PqcDevicePublicKey(
          deviceId: targetDevice.deviceId,
          kemPublicKeyBase64: targetDevice.pqcPublicKey,
          signingPublicKeyBase64: targetDevice.pqcSigningPublicKey,
        ),
      );
    }
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
    required String algorithm,
    required String wrappedKey,
  }) async {
    try {
      if (algorithm == sdk.PqcV2Wire.groupEnvelopeV25Algorithm ||
          wrappedKey.startsWith('${sdk.PqcV2Wire.groupWrapV25Prefix}:')) {
        final localIdentity = await _deviceIdentityService.getIdentity();
        final localPqc = await _devicePqcKeyService.getOrCreateKeyMaterial();
        final localSigning = await _devicePqcSigningKeyService
            .getOrCreateKeyMaterial();
        final senderBindingId = senderDevice.v3KeysetId;
        if (targetDeviceId != localIdentity.id ||
            senderBindingId.isEmpty ||
            !senderDevice.hasUsableMlDsaKey) {
          return null;
        }
        final epoch =
            await sdk.PqcV25GroupEpochCodec(
              sdk.DartPqcPrimitiveSuite(),
            ).unwrapEpoch(
              conversation: sdk.PqcConversation(
                id: conversation.id,
                type: conversation.type,
              ),
              wrappedEpoch: wrappedKey,
              recipient: sdk.PqcDeviceKeyset(
                deviceId: localIdentity.id,
                kemPublicKeyBase64: localPqc.publicKey,
                kemSecretKeyBase64: localPqc.secretKey,
                signingPublicKeyBase64: localSigning.publicKey,
                signingSecretKeyBase64: localSigning.secretKey,
              ),
              trustedSigningKeysByDevice: {
                senderDevice.deviceId: {senderDevice.pqcSigningPublicKey},
              },
              trustedKeysetBindingsByDevice: {
                senderDevice.deviceId: {senderBindingId},
              },
            );
        return epoch?.secretKeyBytes;
      }
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

  static String _withoutTrailingColon(String value) =>
      value.endsWith(':') ? value.substring(0, value.length - 1) : value;
}
