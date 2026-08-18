import 'dart:convert';

import 'models.dart';
import 'primitives.dart';
import 'v2_engine.dart';
import 'v3_attachment_codec.dart';

/// Stable V3 wire contract. It is kept next to the engine so every encoder,
/// decoder and test uses the same protocol identifiers.
abstract final class PqcV3Wire {
  static const protocolVersion = 3;
  static const privatePrefix = 'pqc:v3';
  static const groupPrefix = 'group:v3';
  static const attachmentCipherVersion = PqcV3WireAttachment.cipherVersion;
  static const senderKemPublicKeyField = 'sender_kem_public_key';
}

class PqcV3Engine implements PqcEngine {
  PqcV3Engine({PqcPrimitiveSuite? primitives})
    : primitives = primitives ?? DartPqcPrimitiveSuite() {
    attachment = PqcV3AttachmentCodec(this.primitives);
  }

  final PqcPrimitiveSuite primitives;
  late final PqcV3AttachmentCodec attachment;

  @override
  String get engineId => 'pqc-v3';

  @override
  int get protocolVersion => PqcV3Wire.protocolVersion;

  @override
  String get privatePrefix => PqcV3Wire.privatePrefix;

  @override
  String get groupPrefix => PqcV3Wire.groupPrefix;

  @override
  Set<String> get attachmentCipherVersions => const {
    PqcV3Wire.attachmentCipherVersion,
  };

  @override
  Set<String> get groupEnvelopeReadPrefixes => const {};

  @override
  Set<String> get groupEnvelopeWritePrefixes => const {};

  @override
  Future<String> encodePrivate({
    required PqcConversation conversation,
    required String plaintext,
    required PqcDeviceKeyset sender,
    required Iterable<PqcDevicePublicKey> recipientDevices,
    String messageId = '',
  }) => _encode(
    conversation: conversation,
    plaintext: plaintext,
    sender: sender,
    recipients: recipientDevices.toList(growable: false),
    isGroup: false,
    messageId: messageId,
  );

  @override
  Future<String> encodeGroup({
    required PqcConversation conversation,
    required String plaintext,
    required PqcGroupEpoch epoch,
    PqcDeviceKeyset? sender,
    Iterable<PqcDevicePublicKey> recipientDevices = const [],
    String messageId = '',
  }) {
    if (sender == null) {
      throw ArgumentError('V3 group messages require a signing sender keyset.');
    }
    return _encode(
      conversation: conversation,
      plaintext: plaintext,
      sender: sender,
      recipients: recipientDevices.isEmpty
          ? [sender.publicKey]
          : recipientDevices.toList(growable: false),
      groupEpoch: epoch,
      isGroup: true,
      messageId: messageId,
    );
  }

  @override
  Future<PqcDecodeResult> decodePrivate({
    required PqcConversation conversation,
    required String payload,
    required Iterable<PqcDeviceKeyset> localKeysets,
    required Map<String, Set<String>> trustedSigningKeysByDevice,
  }) => _decode(
    conversation: conversation,
    payload: payload,
    localKeysets: localKeysets,
    trustedSigningKeysByDevice: trustedSigningKeysByDevice,
    expectedGroup: false,
  );

  @override
  Future<PqcDecodeResult> decodeGroup({
    required PqcConversation conversation,
    required String payload,
    required Map<String, PqcGroupEpoch> epochsById,
    Iterable<PqcDeviceKeyset> localKeysets = const [],
    Map<String, Set<String>> trustedSigningKeysByDevice = const {},
    bool requireAuthenticatedSender = false,
  }) async {
    // V3 group messages are recipient-wrapped and signed just like private
    // messages. The epoch map is accepted for API symmetry, but the V3
    // content key is carried by the recipient wrap.
    final result = await _decode(
      conversation: conversation,
      payload: payload,
      localKeysets: localKeysets,
      trustedSigningKeysByDevice: trustedSigningKeysByDevice,
      expectedGroup: true,
    );
    if (result is PqcDecodeError &&
        result.failure == PqcDecodeFailure.keyMissing &&
        epochsById.isNotEmpty) {
      return result;
    }
    return result;
  }

  @override
  bool recognizesPrivate(String payload) =>
      payload.startsWith('${PqcV3Wire.privatePrefix}:');

  @override
  bool recognizesGroup(String payload) =>
      payload.startsWith('${PqcV3Wire.groupPrefix}:');

  @override
  bool recognizesGroupEnvelope(String payload) => false;
  Future<String> _encode({
    required PqcConversation conversation,
    required String plaintext,
    required PqcDeviceKeyset sender,
    required List<PqcDevicePublicKey> recipients,
    required bool isGroup,
    required String messageId,
    PqcGroupEpoch? groupEpoch,
  }) async {
    if (isGroup != conversation.isGroup) {
      throw ArgumentError('V3 conversation type does not match payload kind.');
    }
    if (sender.deviceId.trim().isEmpty ||
        sender.signingPublicKeyBase64.trim().isEmpty) {
      throw ArgumentError('V3 sender keyset is incomplete.');
    }
    _validateRecipients(recipients);
    if (recipients.isEmpty) {
      throw ArgumentError('V3 payload needs at least one recipient device.');
    }
    if (messageId.trim().isEmpty) {
      throw ArgumentError('V3 encryption requires a stable message ID.');
    }
    final contentKey = groupEpoch == null
        ? primitives.randomBytes(32)
        : List<int>.of(groupEpoch.secretKeyBytes);
    if (contentKey.length != 32) {
      throw ArgumentError('V3 content key must be exactly 32 bytes.');
    }
    final associatedData = _messageAssociatedData(
      conversation: conversation,
      messageId: messageId,
      sender: sender,
    );
    final contentBox = await primitives.encryptAead(
      plaintext: utf8.encode(plaintext),
      key: contentKey,
      nonce: primitives.randomBytes(12),
      aad: associatedData,
    );
    final wraps = <Map<String, dynamic>>[];
    for (final recipient in recipients) {
      final kem = primitives.encapsulate(recipient.kemPublicKeyBase64);
      final wrapped = await primitives.encryptAead(
        plaintext: contentKey,
        key: kem.sharedSecret,
        nonce: primitives.randomBytes(12),
        aad: utf8.encode('$messageId:${recipient.deviceId}'),
      );
      wraps.add({
        'device_id': recipient.deviceId,
        'keyset_id': recipient.bindingId,
        'kem_ciphertext': kem.ciphertextBase64,
        'wrapped_key': _encodeBox(wrapped),
      });
    }
    final unsigned = _document(
      conversation: conversation,
      messageId: messageId,
      sender: sender,
      ciphertext: _encodeBox(contentBox),
      wraps: wraps,
      isGroup: isGroup,
    );
    final signature = primitives.sign(
      message: utf8.encode(jsonEncode(unsigned)),
      secretKeyBase64: sender.signingSecretKeyBase64,
    );
    return '${isGroup ? PqcV3Wire.groupPrefix : PqcV3Wire.privatePrefix}:'
        '${_encodeDocument({...unsigned, 'signature': signature})}';
  }

  Future<PqcDecodeResult> _decode({
    required PqcConversation conversation,
    required String payload,
    required Iterable<PqcDeviceKeyset> localKeysets,
    required Map<String, Set<String>> trustedSigningKeysByDevice,
    required bool expectedGroup,
  }) async {
    try {
      final isGroup = recognizesGroup(payload);
      if (isGroup != expectedGroup ||
          (!isGroup && !recognizesPrivate(payload)) ||
          isGroup != conversation.isGroup) {
        return const PqcDecodeError(PqcDecodeFailure.unsupported);
      }
      final document = _decodeDocument(
        payload.substring(
          (isGroup ? PqcV3Wire.groupPrefix : PqcV3Wire.privatePrefix).length +
              1,
        ),
      );
      if (document['protocol_version'] != PqcV3Wire.protocolVersion ||
          document['conversation_id'] != conversation.id ||
          document['conversation_type'] != conversation.type) {
        return const PqcDecodeError(PqcDecodeFailure.bindingMismatch);
      }
      final messageId = document['message_id'] as String? ?? '';
      final senderDeviceId = document['sender_device_id'] as String? ?? '';
      final senderKeysetId = document['sender_keyset_id'] as String? ?? '';
      final senderKemPublicKey =
          document[PqcV3Wire.senderKemPublicKeyField] as String? ?? '';
      final signingPublicKey = document['signing_public_key'] as String? ?? '';
      final signature = document['signature'] as String? ?? '';
      if (messageId.isEmpty ||
          senderDeviceId.isEmpty ||
          senderKeysetId.isEmpty ||
          senderKemPublicKey.isEmpty ||
          signingPublicKey.isEmpty ||
          signature.isEmpty ||
          document['keyset_id'] != senderKeysetId ||
          computeKeysetBindingId(
                senderDeviceId,
                senderKemPublicKey,
                signingPublicKey,
              ) !=
              senderKeysetId) {
        return const PqcDecodeError(PqcDecodeFailure.corrupted);
      }
      final trusted = trustedSigningKeysByDevice[senderDeviceId];
      if (trusted == null || !trusted.contains(signingPublicKey)) {
        return const PqcDecodeError(PqcDecodeFailure.untrustedSender);
      }
      final unsigned = Map<String, dynamic>.from(document)..remove('signature');
      if (!primitives.verify(
        message: utf8.encode(jsonEncode(unsigned)),
        signatureBase64: signature,
        publicKeyBase64: signingPublicKey,
      )) {
        return const PqcDecodeError(PqcDecodeFailure.corrupted);
      }
      final wraps = (document['wraps'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
      PqcDeviceKeyset? local;
      Map<String, dynamic>? selected;
      for (final keyset in localKeysets) {
        final candidate = wraps.where((item) {
          return item['device_id'] == keyset.deviceId &&
              item['keyset_id'] == keyset.bindingId;
        }).firstOrNull;
        if (candidate != null) {
          local = keyset;
          selected = candidate;
          break;
        }
      }
      if (local == null || selected == null) {
        return const PqcDecodeError(PqcDecodeFailure.keyMissing);
      }
      final shared = primitives.decapsulate(
        ciphertextBase64: selected['kem_ciphertext'] as String? ?? '',
        secretKeyBase64: local.kemSecretKeyBase64,
      );
      final contentKey = await primitives.decryptAead(
        box: _decodeBox(selected['wrapped_key'] as String? ?? ''),
        key: shared,
        aad: utf8.encode('$messageId:${local.deviceId}'),
      );
      final clear = await primitives.decryptAead(
        box: _decodeBox(document['ciphertext'] as String? ?? ''),
        key: contentKey,
        aad: _messageAssociatedData(
          conversation: conversation,
          messageId: messageId,
          senderDeviceId: senderDeviceId,
          senderKeysetId: senderKeysetId,
        ),
      );
      return PqcDecoded(
        plaintext: utf8.decode(clear),
        protocolVersion: PqcV3Wire.protocolVersion,
      );
    } catch (error) {
      return PqcDecodeError(
        PqcDecodeFailure.corrupted,
        details: error.runtimeType.toString(),
      );
    }
  }

  Map<String, dynamic> _document({
    required PqcConversation conversation,
    required String messageId,
    required PqcDeviceKeyset sender,
    required String ciphertext,
    required List<Map<String, dynamic>> wraps,
    required bool isGroup,
  }) => {
    'protocol_version': PqcV3Wire.protocolVersion,
    'message_id': messageId,
    'sender_device_id': sender.deviceId,
    'keyset_id': sender.bindingId,
    PqcV3Wire.senderKemPublicKeyField: sender.kemPublicKeyBase64,
    'ciphertext': ciphertext,
    'metadata': const <String, dynamic>{},
    'conversation_id': conversation.id,
    'conversation_type': conversation.type,
    'sender_keyset_id': sender.bindingId,
    'signing_public_key': sender.signingPublicKeyBase64,
    'wraps': wraps,
  };

  List<int> _messageAssociatedData({
    required PqcConversation conversation,
    required String messageId,
    String? senderDeviceId,
    String? senderKeysetId,
    PqcDeviceKeyset? sender,
  }) => utf8.encode(
    jsonEncode({
      'conversation_id': conversation.id,
      'conversation_type': conversation.type,
      'message_id': messageId,
      'sender_device_id': senderDeviceId ?? sender?.deviceId ?? '',
      'keyset_id': senderKeysetId ?? sender?.bindingId ?? '',
    }),
  );

  void _validateRecipients(List<PqcDevicePublicKey> recipients) {
    final ids = <String>{};
    for (final recipient in recipients) {
      if (recipient.deviceId.trim().isEmpty ||
          recipient.kemPublicKeyBase64.trim().isEmpty ||
          recipient.signingPublicKeyBase64.trim().isEmpty ||
          recipient.bindingId.isEmpty ||
          !ids.add(recipient.deviceId)) {
        throw ArgumentError(
          'V3 recipient device/keyset identities are invalid.',
        );
      }
    }
  }
}

String _encodeBox(PqcAeadBox box) =>
    base64Encode(<int>[...box.nonce, ...box.ciphertext, ...box.mac]);

PqcAeadBox _decodeBox(String encoded) {
  final bytes = base64Decode(encoded);
  if (bytes.length < 28) {
    throw const FormatException('Invalid V3 AEAD box.');
  }
  return PqcAeadBox(
    nonce: bytes.sublist(0, 12),
    ciphertext: bytes.sublist(12, bytes.length - 16),
    mac: bytes.sublist(bytes.length - 16),
  );
}

String _encodeDocument(Map<String, dynamic> document) =>
    base64UrlEncode(utf8.encode(jsonEncode(document)));

Map<String, dynamic> _decodeDocument(String encoded) {
  final padded = encoded.padRight(
    encoded.length + ((4 - encoded.length % 4) % 4),
    '=',
  );
  final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('V3 envelope must be an object.');
  }
  return Map<String, dynamic>.from(decoded);
}
