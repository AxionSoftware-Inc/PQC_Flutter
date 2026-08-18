import '../chat_cipher_service.dart';
import '../chat_crypto_context.dart';
import '../durability/key_material_registry.dart';
import '../durability/crypto_durability_models.dart';
import '../../models/conversation.dart';
import '../../core/device/device_identity_service.dart';
import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;
import 'pqc_v3_sdk_primitive_suite.dart';
import 'v3_envelope.dart';

/// Adapter from the app's chat context to the isolated V3 codec.
class V3ChatCipherAlgorithm implements ChatCipherAlgorithm, ChatCipherWriter {
  V3ChatCipherAlgorithm({
    required this.identityService,
    required this.pqcKeyService,
    required this.signingKeyService,
    required this.keyMaterialRegistry,
  }) : _engine = sdk.PqcV3Engine(primitives: PqcV3SdkPrimitiveSuite());

  final DeviceIdentityService identityService;
  final DevicePqcKeyService pqcKeyService;
  final DevicePqcSigningKeyService signingKeyService;
  final KeyMaterialRegistry keyMaterialRegistry;
  final sdk.PqcV3Engine _engine;

  @override
  bool supportsConversation(Conversation conversation) => true;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('pqc:v3:') || payload.startsWith('group:v3:');

  @override
  bool canWritePrefix(String prefix) =>
      prefix == '${sdk.PqcV3Wire.privatePrefix}:' ||
      prefix == '${sdk.PqcV3Wire.groupPrefix}:';

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    if (context.messageId.trim().isEmpty) {
      throw StateError('V3 encryption requires a stable message ID.');
    }
    final current = await keyMaterialRegistry.ensureCurrentKeysetRegistered();
    final identity = await identityService.getIdentity();
    final recipients = <sdk.PqcDevicePublicKey>[];
    // A private envelope must only ever contain the participants' device
    // wraps.  Using the workspace-wide directory here would give unrelated
    // users a valid content-key wrap.
    final participantIds = context.conversation.participantIds.toSet();
    for (final userId in participantIds) {
      final user = context.usersById[userId];
      if (user == null) continue;
      for (final device in user.activeDevices) {
        if (!device.hasUsableMlKemKey || device.v3KeysetId.isEmpty) continue;
        recipients.add(
          sdk.PqcDevicePublicKey(
            deviceId: device.deviceId,
            kemPublicKeyBase64: device.pqcPublicKey,
            signingPublicKeyBase64: device.pqcSigningPublicKey,
          ),
        );
      }
    }
    if (!recipients.any((item) => item.deviceId == identity.id)) {
      recipients.add(
        sdk.PqcDevicePublicKey(
          deviceId: identity.id,
          kemPublicKeyBase64: current.pqcPublicKey,
          signingPublicKeyBase64: current.pqcSigningPublicKey,
        ),
      );
    }
    final sender = sdk.PqcDeviceKeyset(
      deviceId: identity.id,
      kemPublicKeyBase64: current.pqcPublicKey,
      kemSecretKeyBase64: current.pqcSecretKey,
      signingPublicKeyBase64: current.pqcSigningPublicKey,
      signingSecretKeyBase64: current.pqcSigningSecretKey,
    );
    return context.conversation.isGroup
        ? _engine.encodeGroup(
            conversation: sdk.PqcConversation(
              id: context.conversation.id,
              type: context.conversation.type,
            ),
            plaintext: plaintext,
            epoch: sdk.PqcGroupEpoch(
              epochId: context.messageId,
              secretKeyBytes: _engine.primitives.randomBytes(32),
            ),
            sender: sender,
            recipientDevices: recipients,
            messageId: context.messageId,
          )
        : _engine.encodePrivate(
            conversation: sdk.PqcConversation(
              id: context.conversation.id,
              type: context.conversation.type,
            ),
            plaintext: plaintext,
            sender: sender,
            recipientDevices: recipients,
            messageId: context.messageId,
          );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    try {
      final envelope = V3Envelope.decode(payload);
      if (!_isTrustedSender(context: context, envelope: envelope)) {
        throw StateError('V3 sender keyset is not trusted for this message.');
      }
      final current = await keyMaterialRegistry.ensureCurrentKeysetRegistered();
      final candidates = [
        current,
        ...await keyMaterialRegistry.readHistoricalDecryptKeysets(),
      ];
      final result = context.conversation.isGroup
          ? await _engine.decodeGroup(
              conversation: sdk.PqcConversation(
                id: context.conversation.id,
                type: context.conversation.type,
              ),
              payload: payload,
              epochsById: const {},
              localKeysets: candidates.map(_toSdkKeyset),
              trustedSigningKeysByDevice: _trustedSigningKeys(context),
            )
          : await _engine.decodePrivate(
              conversation: sdk.PqcConversation(
                id: context.conversation.id,
                type: context.conversation.type,
              ),
              payload: payload,
              localKeysets: candidates.map(_toSdkKeyset),
              trustedSigningKeysByDevice: _trustedSigningKeys(context),
            );
      return switch (result) {
        sdk.PqcDecoded(:final plaintext) => plaintext,
        _ => '[decrypt-error]',
      };
    } catch (_) {
      // A lost/revoked device key must classify the message instead of
      // aborting the entire conversation sync with a SecretBox MAC error.
      return '[decrypt-error]';
    }
  }

  sdk.PqcDeviceKeyset _toSdkKeyset(KeysetSnapshot keyset) =>
      sdk.PqcDeviceKeyset(
        deviceId: keyset.deviceId,
        kemPublicKeyBase64: keyset.pqcPublicKey,
        kemSecretKeyBase64: keyset.pqcSecretKey,
        signingPublicKeyBase64: keyset.pqcSigningPublicKey,
        signingSecretKeyBase64: keyset.pqcSigningSecretKey,
      );

  Map<String, Set<String>> _trustedSigningKeys(ChatCryptoContext context) {
    final trusted = <String, Set<String>>{};
    for (final user in context.usersById.values) {
      for (final device in user.devices) {
        if (!device.hasUsableMlDsaKey) continue;
        trusted
            .putIfAbsent(device.deviceId, () => <String>{})
            .add(device.pqcSigningPublicKey);
      }
    }
    return trusted;
  }

  static bool _isTrustedSender({
    required ChatCryptoContext context,
    required V3Envelope envelope,
  }) {
    final senderId = context.senderId;
    // Legacy conversation previews do not expose a sender id.  Full message
    // sync and realtime events always do, and therefore enforce this binding.
    if (senderId == null) return true;
    if (!context.conversation.participantIds.contains(senderId)) return false;
    final sender = context.usersById[senderId];
    if (sender == null) return false;
    return sender.devices.any(
      (device) =>
          device.deviceId == envelope.senderDeviceId &&
          device.v3KeysetId == envelope.senderKeysetId &&
          device.pqcPublicKey == envelope.senderKemPublicKey &&
          device.pqcSigningAlgorithm == 'ml-dsa-65' &&
          device.pqcSigningPublicKey == envelope.signingPublicKey,
    );
  }
}
