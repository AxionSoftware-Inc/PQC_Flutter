import '../chat_cipher_service.dart';
import '../chat_crypto_context.dart';
import '../durability/key_material_registry.dart';
import '../../models/conversation.dart';
import '../../core/device/device_identity_service.dart';
import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import 'pqc_v3_crypto_adapter.dart';
import 'v3_message_codecs.dart';

/// Adapter from the app's chat context to the isolated V3 codec.
class V3ChatCipherAlgorithm implements ChatCipherAlgorithm {
  V3ChatCipherAlgorithm({
    required this.identityService,
    required this.pqcKeyService,
    required this.signingKeyService,
    required this.keyMaterialRegistry,
    V3MessageCodec? codec,
  }) : _codec =
           codec ??
           V3MessageCodec(
             crypto: PqcV3CryptoAdapter(
               keyService: pqcKeyService,
               signingService: signingKeyService,
             ),
           );

  final DeviceIdentityService identityService;
  final DevicePqcKeyService pqcKeyService;
  final DevicePqcSigningKeyService signingKeyService;
  final KeyMaterialRegistry keyMaterialRegistry;
  final V3MessageCodec _codec;

  @override
  bool supportsConversation(Conversation conversation) => true;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('pqc:v3:') || payload.startsWith('group:v3:');

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
    final recipients = <V3DeviceRecipient>[];
    for (final user in context.usersById.values) {
      for (final device in user.activeDevices) {
        if (!device.hasUsableMlKemKey || device.keysetId.isEmpty) continue;
        recipients.add(
          V3DeviceRecipient(
            deviceId: device.deviceId,
            keysetId: device.keysetId,
            publicKey: device.pqcPublicKey,
          ),
        );
      }
    }
    if (!recipients.any((item) => item.deviceId == identity.id)) {
      recipients.add(
        V3DeviceRecipient(
          deviceId: identity.id,
          keysetId: current.keysetId,
          publicKey: current.pqcPublicKey,
        ),
      );
    }
    final codecContext = V3CodecContext(
      conversationId: context.conversation.id,
      conversationType: context.conversation.type,
      messageId: context.messageId,
      senderDeviceId: identity.id,
      senderKeysetId: current.keysetId,
      signingPublicKey: current.pqcSigningPublicKey,
      localDeviceId: identity.id,
      localKeysetId: current.keysetId,
      recipients: recipients,
    );
    return context.conversation.isGroup
        ? _codec.encryptGroup(context: codecContext, plaintext: plaintext)
        : _codec.encryptPrivate(context: codecContext, plaintext: plaintext);
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    try {
      final current = await keyMaterialRegistry.ensureCurrentKeysetRegistered();
      final candidates = <dynamic>[
        current,
        ...await keyMaterialRegistry.readHistoricalDecryptKeysets(),
      ];
      Object? lastError;
      for (final keyset in candidates) {
        try {
          // A reinstall creates a new installation id.  Historical keysets
          // belong to the prior installation, so their recipient wrap must be
          // resolved with *their* device id, not the newly-created one.  The
          // envelope still requires both the old device id and exact keyset
          // id, therefore trying retained keysets cannot decrypt a payload
          // that was not addressed to this account's retained key material.
          return await _codec.decrypt(
            context: V3CodecContext(
              conversationId: context.conversation.id,
              conversationType: context.conversation.type,
              messageId: context.messageId,
              senderDeviceId: '',
              senderKeysetId: '',
              signingPublicKey: '',
              localDeviceId: keyset.deviceId,
              localKeysetId: keyset.keysetId,
              localSecretKey: keyset.pqcSecretKey,
            ),
            payload: payload,
          );
        } catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) throw lastError;
      throw StateError('No local V3 keyset is available.');
    } catch (_) {
      // A lost/revoked device key must classify the message instead of
      // aborting the entire conversation sync with a SecretBox MAC error.
      return '[decrypt-error]';
    }
  }
}
