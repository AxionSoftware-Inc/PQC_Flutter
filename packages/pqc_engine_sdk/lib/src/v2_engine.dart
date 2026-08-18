import 'models.dart';
import 'primitives.dart';
import 'v2_attachment_codec.dart';
import 'v2_group_codec.dart';
import 'v2_private_codec.dart';
import 'v25_group_epoch_codec.dart';

abstract interface class PqcEngine {
  String get engineId;
  int get protocolVersion;
  String get privatePrefix;
  String get groupPrefix;
  Set<String> get attachmentCipherVersions;
  Set<String> get groupEnvelopeReadPrefixes;
  Set<String> get groupEnvelopeWritePrefixes;

  Future<String> encodePrivate({
    required PqcConversation conversation,
    required String plaintext,
    required PqcDeviceKeyset sender,
    required Iterable<PqcDevicePublicKey> recipientDevices,
  });

  Future<PqcDecodeResult> decodePrivate({
    required PqcConversation conversation,
    required String payload,
    required Iterable<PqcDeviceKeyset> localKeysets,
    required Map<String, Set<String>> trustedSigningKeysByDevice,
  });

  Future<String> encodeGroup({
    required PqcConversation conversation,
    required String plaintext,
    required PqcGroupEpoch epoch,
    PqcDeviceKeyset? sender,
  });

  Future<PqcDecodeResult> decodeGroup({
    required PqcConversation conversation,
    required String payload,
    required Map<String, PqcGroupEpoch> epochsById,
    Map<String, Set<String>> trustedSigningKeysByDevice = const {},
    bool requireAuthenticatedSender = false,
  });

  bool recognizesPrivate(String payload);
  bool recognizesGroup(String payload);
  bool recognizesGroupEnvelope(String payload);
}

class PqcV2Engine implements PqcEngine {
  PqcV2Engine({
    PqcPrimitiveSuite? primitives,
    this.enableV25GroupEnvelopeWriter = false,
  }) : primitives = primitives ?? DartPqcPrimitiveSuite() {
    private = PqcV2PrivateCodec(this.primitives);
    group = PqcV2GroupCodec(this.primitives);
    groupEpochV25 = PqcV25GroupEpochCodec(this.primitives);
    attachment = PqcV2AttachmentCodec(this.primitives);
  }

  final PqcPrimitiveSuite primitives;
  final bool enableV25GroupEnvelopeWriter;
  late final PqcV2PrivateCodec private;
  late final PqcV2GroupCodec group;
  late final PqcV25GroupEpochCodec groupEpochV25;
  late final PqcV2AttachmentCodec attachment;

  @override
  String get engineId => enableV25GroupEnvelopeWriter ? 'pqc-v2.5' : 'pqc-v2';

  @override
  int get protocolVersion => PqcV2Wire.protocolVersion;

  @override
  String get privatePrefix => PqcV2Wire.privatePrefix;

  @override
  String get groupPrefix => PqcV2Wire.groupPrefix;

  @override
  Set<String> get attachmentCipherVersions => const {
    PqcV2Wire.attachmentCipherVersion,
  };

  @override
  Set<String> get groupEnvelopeReadPrefixes => const {
    PqcV2Wire.groupWrapPrefix,
    PqcV2Wire.groupWrapV25Prefix,
  };

  @override
  Set<String> get groupEnvelopeWritePrefixes => enableV25GroupEnvelopeWriter
      ? const {PqcV2Wire.groupWrapV25Prefix}
      : const {PqcV2Wire.groupWrapPrefix};

  @override
  Future<String> encodePrivate({
    required PqcConversation conversation,
    required String plaintext,
    required PqcDeviceKeyset sender,
    required Iterable<PqcDevicePublicKey> recipientDevices,
  }) => private.encrypt(
    conversation: conversation,
    plaintext: plaintext,
    sender: sender,
    recipientDevices: recipientDevices,
  );

  @override
  Future<PqcDecodeResult> decodePrivate({
    required PqcConversation conversation,
    required String payload,
    required Iterable<PqcDeviceKeyset> localKeysets,
    required Map<String, Set<String>> trustedSigningKeysByDevice,
  }) => private.decrypt(
    conversation: conversation,
    payload: payload,
    localKeysets: localKeysets,
    trustedSigningKeysByDevice: trustedSigningKeysByDevice,
  );

  @override
  Future<String> encodeGroup({
    required PqcConversation conversation,
    required String plaintext,
    required PqcGroupEpoch epoch,
    PqcDeviceKeyset? sender,
  }) => group.encrypt(
    conversation: conversation,
    plaintext: plaintext,
    epoch: epoch,
    sender: sender,
  );

  @override
  Future<PqcDecodeResult> decodeGroup({
    required PqcConversation conversation,
    required String payload,
    required Map<String, PqcGroupEpoch> epochsById,
    Map<String, Set<String>> trustedSigningKeysByDevice = const {},
    bool requireAuthenticatedSender = false,
  }) => group.decrypt(
    conversation: conversation,
    payload: payload,
    epochsById: epochsById,
    trustedSigningKeysByDevice: trustedSigningKeysByDevice,
    requireAuthenticatedSender: requireAuthenticatedSender,
  );

  @override
  bool recognizesPrivate(String payload) =>
      payload.startsWith('$privatePrefix:');

  @override
  bool recognizesGroup(String payload) => payload.startsWith('$groupPrefix:');

  @override
  bool recognizesGroupEnvelope(String payload) =>
      groupEnvelopeReadPrefixes.any((prefix) => payload.startsWith('$prefix:'));
}
