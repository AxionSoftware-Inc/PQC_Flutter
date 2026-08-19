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
    String messageId = '',
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
    Iterable<PqcDevicePublicKey> recipientDevices = const [],
    String messageId = '',
  });

  Future<PqcDecodeResult> decodeGroup({
    required PqcConversation conversation,
    required String payload,
    required Map<String, PqcGroupEpoch> epochsById,
    Iterable<PqcDeviceKeyset> localKeysets = const [],
    Map<String, Set<String>> trustedSigningKeysByDevice = const {},
    bool requireAuthenticatedSender = false,
  });

  bool recognizesPrivate(String payload);
  bool recognizesGroup(String payload);
  bool recognizesGroupEnvelope(String payload);
}

/// Engine capability for the separately versioned group-key envelope.
///
/// V3 messages deliberately do not implement this interface: during the V3
/// rollout the application keeps the frozen V2 group-envelope writer as its
/// compatibility path. Keeping this capability explicit prevents a message
/// engine from being selected for an operation it cannot actually encode.
abstract interface class PqcGroupEnvelopeEngine {
  Future<String> encodeGroupEnvelope({
    required PqcConversation conversation,
    required PqcGroupEpoch epoch,
    required PqcDeviceKeyset sender,
    required PqcDevicePublicKey recipient,
  });

  Future<PqcGroupEpoch?> decodeGroupEnvelope({
    required PqcConversation conversation,
    required String wrappedEpoch,
    required PqcDeviceKeyset recipient,
    String? epochId,
    Map<String, Set<String>> trustedSigningKeysByDevice,
    Map<String, Set<String>> trustedKeysetBindingsByDevice,
  });
}

class PqcV2Engine implements PqcEngine, PqcGroupEnvelopeEngine {
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
    String messageId = '',
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
    Iterable<PqcDevicePublicKey> recipientDevices = const [],
    String messageId = '',
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
    Iterable<PqcDeviceKeyset> localKeysets = const [],
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
  Future<String> encodeGroupEnvelope({
    required PqcConversation conversation,
    required PqcGroupEpoch epoch,
    required PqcDeviceKeyset sender,
    required PqcDevicePublicKey recipient,
  }) => enableV25GroupEnvelopeWriter
      ? groupEpochV25.wrapEpoch(
          conversation: conversation,
          epoch: epoch,
          sender: sender,
          recipient: recipient,
        )
      : group.wrapEpoch(
          conversation: conversation,
          epoch: epoch,
          sender: sender,
          recipient: recipient,
        );

  @override
  Future<PqcGroupEpoch?> decodeGroupEnvelope({
    required PqcConversation conversation,
    required String wrappedEpoch,
    required PqcDeviceKeyset recipient,
    String? epochId,
    Map<String, Set<String>> trustedSigningKeysByDevice = const {},
    Map<String, Set<String>> trustedKeysetBindingsByDevice = const {},
  }) {
    if (wrappedEpoch.startsWith('${PqcV2Wire.groupWrapV25Prefix}:')) {
      return groupEpochV25.unwrapEpoch(
        conversation: conversation,
        wrappedEpoch: wrappedEpoch,
        recipient: recipient,
        trustedSigningKeysByDevice: trustedSigningKeysByDevice,
        trustedKeysetBindingsByDevice: trustedKeysetBindingsByDevice,
      );
    }
    final resolvedEpochId = epochId;
    if (resolvedEpochId == null || resolvedEpochId.isEmpty) {
      return Future.value(null);
    }
    return group.unwrapEpoch(
      conversation: conversation,
      epochId: resolvedEpochId,
      wrappedEpoch: wrappedEpoch,
      recipient: recipient,
      trustedSigningKeysByDevice: trustedSigningKeysByDevice,
    );
  }

  @override
  bool recognizesPrivate(String payload) =>
      payload.startsWith('$privatePrefix:');

  @override
  bool recognizesGroup(String payload) => payload.startsWith('$groupPrefix:');

  @override
  bool recognizesGroupEnvelope(String payload) =>
      groupEnvelopeReadPrefixes.any((prefix) => payload.startsWith('$prefix:'));
}
