import 'package:crypto_core/crypto_core.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

class SdkV2PrivateChatAlgorithm implements ChatCipherAlgorithm {
  SdkV2PrivateChatAlgorithm({
    required this.deviceIdentityService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    required this.keyMaterialRegistry,
    sdk.PqcV2Engine? engine,
  }) : _engine = engine ?? sdk.PqcV2Engine();

  final DeviceIdentityService deviceIdentityService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final KeyMaterialRegistry keyMaterialRegistry;
  final sdk.PqcV2Engine _engine;

  @override
  bool supportsConversation(Conversation conversation) => !conversation.isGroup;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${sdk.PqcV2Wire.privatePrefix}:');

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    final sender = await _currentKeyset();
    final recipients = _recipientDevices(context);
    if (context.conversation.participantIds.length > 1 &&
        !recipients.any((item) => item.deviceId != sender.deviceId)) {
      throw ChatEncryptionException(
        'All active private-chat participant devices need ML-KEM keys.',
      );
    }
    return _engine.private.encrypt(
      conversation: _conversation(context.conversation),
      plaintext: plaintext,
      sender: sender,
      recipientDevices: recipients,
    );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    final result = await _engine.private.decrypt(
      conversation: _conversation(context.conversation),
      payload: payload,
      localKeysets: await _readableKeysets(),
      trustedSigningKeysByDevice: await _trustedSigningKeys(context.usersById),
    );
    return _mapDecodeResult(result);
  }

  Future<sdk.PqcDeviceKeyset> _currentKeyset() async {
    final snapshot = await keyMaterialRegistry.ensureCurrentKeysetRegistered();
    return _keyset(snapshot);
  }

  Future<List<sdk.PqcDeviceKeyset>> _readableKeysets() async {
    await keyMaterialRegistry.ensureCurrentKeysetRegistered();
    final snapshots = await keyMaterialRegistry.readAllKeysets();
    final unique = <String, sdk.PqcDeviceKeyset>{};
    for (final snapshot in snapshots) {
      if (!snapshot.isHistoricalReadEnabled) {
        continue;
      }
      final value = _keyset(snapshot);
      unique[value.keysetId] = value;
    }
    return unique.values.toList(growable: false);
  }

  List<sdk.PqcDevicePublicKey> _recipientDevices(ChatCryptoContext context) {
    final unique = <String, sdk.PqcDevicePublicKey>{};
    for (final participantId in context.conversation.participantIds) {
      final user = context.usersById[participantId];
      if (user == null) {
        continue;
      }
      for (final device in user.devices) {
        if (!device.isActive || !device.hasUsableMlKemKey) {
          continue;
        }
        final value = sdk.PqcDevicePublicKey(
          deviceId: device.deviceId,
          kemPublicKeyBase64: device.pqcPublicKey,
          signingPublicKeyBase64: device.pqcSigningPublicKey,
        );
        final existing = unique[device.deviceId];
        if (existing != null &&
            existing.kemPublicKeyBase64 != value.kemPublicKeyBase64) {
          throw StateError(
            'Conflicting active keysets for device ${device.deviceId}.',
          );
        }
        unique[device.deviceId] = value;
      }
    }
    return unique.values.toList(growable: false);
  }

  Future<Map<String, Set<String>>> _trustedSigningKeys(
    Map<int, AppUser> usersById,
  ) async {
    final trusted = <String, Set<String>>{};
    for (final user in usersById.values) {
      for (final device in user.devices) {
        if (!device.hasUsableMlDsaKey) {
          continue;
        }
        trusted
            .putIfAbsent(device.deviceId, () => <String>{})
            .add(device.pqcSigningPublicKey);
      }
    }
    final snapshots = await keyMaterialRegistry.readAllKeysets();
    for (final snapshot in snapshots) {
      if (!snapshot.isHistoricalReadEnabled ||
          snapshot.pqcSigningPublicKey.isEmpty) {
        continue;
      }
      trusted
          .putIfAbsent(snapshot.deviceId, () => <String>{})
          .add(snapshot.pqcSigningPublicKey);
    }
    return trusted;
  }

  sdk.PqcDeviceKeyset _keyset(KeysetSnapshot snapshot) {
    return sdk.PqcDeviceKeyset(
      deviceId: snapshot.deviceId,
      kemPublicKeyBase64: snapshot.pqcPublicKey,
      kemSecretKeyBase64: snapshot.pqcSecretKey,
      signingPublicKeyBase64: snapshot.pqcSigningPublicKey,
      signingSecretKeyBase64: snapshot.pqcSigningSecretKey,
    );
  }
}

class SdkV2GroupChatAlgorithm implements ChatCipherAlgorithm {
  SdkV2GroupChatAlgorithm({
    required this.groupKeyStore,
    sdk.PqcV2Engine? engine,
  }) : _engine = engine ?? sdk.PqcV2Engine();

  final GroupKeyProvider groupKeyStore;
  final sdk.PqcV2Engine _engine;

  @override
  bool supportsConversation(Conversation conversation) => conversation.isGroup;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${sdk.PqcV2Wire.groupPrefix}:');

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    final key = await groupKeyStore.getOrCreateKey(
      conversation: context.conversation,
      usersById: context.usersById,
    );
    return _engine.group.encrypt(
      conversation: _conversation(context.conversation),
      plaintext: plaintext,
      epoch: sdk.PqcGroupEpoch(
        epochId: key.keyId,
        secretKeyBytes: key.secretKeyBytes,
      ),
    );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    final metadata = _engine.group.inspect(payload);
    if (metadata == null) {
      return '[decrypt-error]';
    }
    final key = await groupKeyStore.getExistingKey(
      conversation: context.conversation,
      usersById: context.usersById,
      requestedKeyId: metadata.epochId,
    );
    if (key == null) {
      return '[history-recovery-pending]';
    }
    final result = await _engine.group.decrypt(
      conversation: _conversation(context.conversation),
      payload: payload,
      epochsById: {
        key.keyId: sdk.PqcGroupEpoch(
          epochId: key.keyId,
          secretKeyBytes: key.secretKeyBytes,
        ),
      },
    );
    return _mapDecodeResult(result);
  }
}

sdk.PqcConversation _conversation(Conversation conversation) {
  return sdk.PqcConversation(id: conversation.id, type: conversation.type);
}

String _mapDecodeResult(sdk.PqcDecodeResult result) {
  if (result is sdk.PqcDecoded) {
    return result.plaintext;
  }
  final failure = (result as sdk.PqcDecodeError).failure;
  return switch (failure) {
    sdk.PqcDecodeFailure.unsupported => '[history-unavailable]',
    sdk.PqcDecodeFailure.keyMissing => '[history-recovery-pending]',
    _ => '[decrypt-error]',
  };
}
