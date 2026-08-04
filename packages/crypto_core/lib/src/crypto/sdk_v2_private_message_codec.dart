import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

import 'package:crypto_core/src/core/device/device_identity_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_key_service.dart';
import 'package:crypto_core/src/core/device/device_pqc_signing_key_service.dart';
import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';

import 'durability/key_material_registry.dart';
import 'message_codec.dart';

/// Flutter host adapter for the frozen standalone V2 SDK.
///
/// Device identity, secure storage and the recovery registry remain app-owned.
/// The SDK owns the V2 wire-format cryptography and decoder classification.
/// This class deliberately preserves [PqcPrivateMessageCodec]'s public API so
/// the chat layer cannot accidentally select a second writer.
class SdkV2PrivateMessageCodec extends PqcPrivateMessageCodec {
  SdkV2PrivateMessageCodec({
    required super.deviceIdentityService,
    required super.devicePqcKeyService,
    required super.devicePqcSigningKeyService,
    required KeyMaterialRegistry keyMaterialRegistry,
    sdk.PqcV2Engine? engine,
  }) : _identityService = deviceIdentityService,
       _pqcKeyService = devicePqcKeyService,
       _signingKeyService = devicePqcSigningKeyService,
       _keyMaterialRegistry = keyMaterialRegistry,
       _engine = engine ?? sdk.PqcV2Engine(),
       super(keyMaterialRegistry: keyMaterialRegistry);

  final DeviceIdentityService _identityService;
  final DevicePqcKeyService _pqcKeyService;
  final DevicePqcSigningKeyService _signingKeyService;
  final KeyMaterialRegistry _keyMaterialRegistry;
  final sdk.PqcV2Engine _engine;

  @override
  Future<String> encrypt({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final identity = await _identityService.getIdentity();
    final kem = await _pqcKeyService.getOrCreateKeyMaterial();
    final signing = await _signingKeyService.getOrCreateKeyMaterial();
    final sender = sdk.PqcDeviceKeyset(
      deviceId: identity.id,
      kemPublicKeyBase64: kem.publicKey,
      kemSecretKeyBase64: kem.secretKey,
      signingPublicKeyBase64: signing.publicKey,
      signingSecretKeyBase64: signing.secretKey,
    );
    final recipients = _recipientDevices(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    if (recipients.isEmpty) {
      throw StateError('No active ML-KEM recipient device is available.');
    }
    return _engine.private.encrypt(
      conversation: sdk.PqcConversation(
        id: conversation.id,
        type: conversation.type,
      ),
      plaintext: plaintext,
      sender: sender,
      recipientDevices: recipients,
    );
  }

  @override
  Future<String> decrypt({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    final keysets = await _localKeysets();
    final result = await _engine.private.decrypt(
      conversation: sdk.PqcConversation(
        id: conversation.id,
        type: conversation.type,
      ),
      payload: payload,
      localKeysets: keysets,
      trustedSigningKeysByDevice: _trustedSigningKeys(usersById),
    );
    return switch (result) {
      sdk.PqcDecoded(:final plaintext) => plaintext,
      sdk.PqcDecodeError(failure: sdk.PqcDecodeFailure.keyMissing) =>
        '[history-recovery-pending]',
      sdk.PqcDecodeError(failure: sdk.PqcDecodeFailure.unsupported) =>
        '[history-unavailable]',
      _ => '[decrypt-error]',
    };
  }

  List<sdk.PqcDevicePublicKey> _recipientDevices({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final devices = <String, sdk.PqcDevicePublicKey>{};
    for (final participantId in conversation.participantIds) {
      final user = usersById[participantId];
      if (user == null) {
        continue;
      }
      for (final device in user.devices) {
        if (!device.isActive || !device.hasUsableMlKemKey) {
          continue;
        }
        devices[device.deviceId] = sdk.PqcDevicePublicKey(
          deviceId: device.deviceId,
          kemPublicKeyBase64: device.pqcPublicKey,
          signingPublicKeyBase64: device.pqcSigningPublicKey,
        );
      }
    }
    return devices.values.toList(growable: false);
  }

  Future<List<sdk.PqcDeviceKeyset>> _localKeysets() async {
    final snapshots = await _keyMaterialRegistry.readHistoricalDecryptKeysets();
    return snapshots
        .map(
          (snapshot) => sdk.PqcDeviceKeyset(
            deviceId: snapshot.deviceId,
            kemPublicKeyBase64: snapshot.pqcPublicKey,
            kemSecretKeyBase64: snapshot.pqcSecretKey,
            signingPublicKeyBase64: snapshot.pqcSigningPublicKey,
            signingSecretKeyBase64: snapshot.pqcSigningSecretKey,
          ),
        )
        .toList(growable: false);
  }

  Map<String, Set<String>> _trustedSigningKeys(Map<int, AppUser> usersById) {
    final trusted = <String, Set<String>>{};
    for (final user in usersById.values) {
      for (final device in user.devices) {
        if (device.pqcSigningPublicKey.isEmpty) {
          continue;
        }
        trusted
            .putIfAbsent(device.deviceId, () => <String>{})
            .add(device.pqcSigningPublicKey);
      }
    }
    return trusted;
  }
}
