import '../durability/crypto_durability_models.dart';
import 'v2_compatibility_decoder.dart';
import 'v3_engine_module.dart';
import 'v3_message_codecs.dart';
import 'v3_envelope.dart';

class V3CodecAdapters {
  const V3CodecAdapters({required this.codec, this.v2Compatibility});

  final V3MessageCodec codec;
  final V2CompatibilityDecoder? v2Compatibility;

  V3EngineModule module() => V3EngineModule(
    formatId: 'pqc-v3-production-candidate',
    privatePrefix: 'pqc:v3:',
    groupPrefix: 'group:v3:',
    encoder: _Encoder(codec),
    decoder: _Decoder(codec, v2Compatibility),
  );
}

class _Encoder implements V3Encoder {
  const _Encoder(this.codec);
  final V3MessageCodec codec;

  @override
  Future<String> encode({
    required String plaintext,
    required Map<String, dynamic> context,
  }) {
    final codecContext = _context(context);
    final isGroup = context['is_group'] == true;
    return isGroup
        ? codec.encryptGroup(context: codecContext, plaintext: plaintext)
        : codec.encryptPrivate(context: codecContext, plaintext: plaintext);
  }
}

class _Decoder implements V3Decoder {
  const _Decoder(this.codec, this.v2Compatibility);
  final V3MessageCodec codec;
  final V2CompatibilityDecoder? v2Compatibility;

  @override
  Future<DecryptionOutcome> decode({
    required String payload,
    required Map<String, dynamic> context,
  }) async {
    if (v2Compatibility?.canDecode(payload) == true) {
      final plaintext = await v2Compatibility!.decode(payload);
      return DecryptSuccess(
        plaintext: plaintext,
        format: PayloadFormatDescriptor(
          formatId: 'v2-compatibility-reader',
          payloadKind: payload.startsWith('group:v2:')
              ? PayloadKind.groupMessage
              : PayloadKind.privateMessage,
          prefix: payload.startsWith('group:v2:') ? 'group:v2:' : 'pqc:v2:',
          introducedAtVersion: '2.0.0',
          decryptSupported: true,
        ),
      );
    }
    final plaintext = await codec.decrypt(
      context: _context(context),
      payload: payload,
    );
    final envelope = V3Envelope.decode(payload);
    return DecryptSuccess(
      plaintext: plaintext,
      format: PayloadFormatDescriptor(
        formatId: envelope.isGroup ? 'group-message-v3' : 'pqc-private-v3',
        payloadKind: envelope.isGroup
            ? PayloadKind.groupMessage
            : PayloadKind.privateMessage,
        prefix: envelope.prefix,
        introducedAtVersion: '3.0.0',
        decryptSupported: true,
        writeEnabled: true,
      ),
    );
  }
}

V3CodecContext _context(Map<String, dynamic> value) {
  return V3CodecContext(
    conversationId: value['conversation_id'] as int,
    conversationType: value['conversation_type'] as String,
    messageId: value['message_id'] as String,
    senderDeviceId: value['sender_device_id'] as String,
    senderKeysetId: value['sender_keyset_id'] as String,
    signingPublicKey: value['signing_public_key'] as String,
    localDeviceId: value['local_device_id'] as String,
    localKeysetId: value['local_keyset_id'] as String,
    recipients: (value['recipients'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => V3DeviceRecipient(
            deviceId: item['device_id'] as String,
            keysetId: item['keyset_id'] as String,
            publicKey: item['public_key'] as String,
          ),
        )
        .toList(growable: false),
    groupEpochKey: (value['group_epoch_key'] as List<dynamic>?)?.cast<int>(),
  );
}
