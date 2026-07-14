import 'dart:convert';

import 'v3_protocol_contract.dart';

class V3Envelope {
  const V3Envelope({
    required this.isGroup,
    required this.messageId,
    required this.senderDeviceId,
    required this.keysetId,
    required this.ciphertext,
    this.metadata = const {},
    this.conversationId,
    this.conversationType,
    this.senderKeysetId,
    this.signingPublicKey,
    this.wraps = const [],
    this.signature,
  });

  final bool isGroup;
  final String messageId;
  final String senderDeviceId;
  final String keysetId;
  final String ciphertext;
  final Map<String, dynamic> metadata;
  final int? conversationId;
  final String? conversationType;
  final String? senderKeysetId;
  final String? signingPublicKey;
  final List<V3RecipientWrap> wraps;
  final String? signature;

  String get prefix => isGroup
      ? V3ProtocolContract.groupPrefix
      : V3ProtocolContract.privatePrefix;

  Map<String, dynamic> toJson({bool includeSignature = true}) => {
    'protocol_version': V3ProtocolContract.protocolVersion,
    'message_id': messageId,
    'sender_device_id': senderDeviceId,
    'keyset_id': keysetId,
    'ciphertext': ciphertext,
    'metadata': metadata,
    if (conversationId != null) 'conversation_id': conversationId,
    if (conversationType != null) 'conversation_type': conversationType,
    if (senderKeysetId != null) 'sender_keyset_id': senderKeysetId,
    if (signingPublicKey != null) 'signing_public_key': signingPublicKey,
    if (wraps.isNotEmpty) 'wraps': wraps.map((item) => item.toJson()).toList(),
    if (includeSignature && signature != null) 'signature': signature,
  };

  String encode() =>
      '$prefix:${base64UrlEncode(utf8.encode(jsonEncode(toJson())))}';

  String unsignedCanonicalJson() => jsonEncode(toJson(includeSignature: false));

  static V3Envelope decode(String payload) {
    final isGroup = payload.startsWith('${V3ProtocolContract.groupPrefix}:');
    final isPrivate = payload.startsWith(
      '${V3ProtocolContract.privatePrefix}:',
    );
    if (!isGroup && !isPrivate) {
      throw const FormatException('Unsupported v3 payload prefix.');
    }
    final encoded = payload
        .substring(payload.indexOf(':') + 1)
        .split(':')
        .skip(1)
        .join(':');
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(encoded)))
            as Map<String, dynamic>;
    if (decoded['protocol_version'] != V3ProtocolContract.protocolVersion) {
      throw const FormatException('Unsupported v3 protocol version.');
    }
    return V3Envelope(
      isGroup: isGroup,
      messageId: decoded['message_id'] as String? ?? '',
      senderDeviceId: decoded['sender_device_id'] as String? ?? '',
      keysetId: decoded['keyset_id'] as String? ?? '',
      ciphertext: decoded['ciphertext'] as String? ?? '',
      metadata: Map<String, dynamic>.from(
        decoded['metadata'] as Map? ?? const {},
      ),
      conversationId: decoded['conversation_id'] as int?,
      conversationType: decoded['conversation_type'] as String?,
      senderKeysetId: decoded['sender_keyset_id'] as String?,
      signingPublicKey: decoded['signing_public_key'] as String?,
      wraps: (decoded['wraps'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => V3RecipientWrap.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
      signature: decoded['signature'] as String?,
    );
  }
}

class V3RecipientWrap {
  const V3RecipientWrap({
    required this.deviceId,
    required this.keysetId,
    required this.kemCiphertext,
    required this.wrappedKey,
  });

  final String deviceId;
  final String keysetId;
  final String kemCiphertext;
  final String wrappedKey;

  Map<String, dynamic> toJson() => {
    'device_id': deviceId,
    'keyset_id': keysetId,
    'kem_ciphertext': kemCiphertext,
    'wrapped_key': wrappedKey,
  };

  factory V3RecipientWrap.fromJson(Map<String, dynamic> json) =>
      V3RecipientWrap(
        deviceId: json['device_id'] as String? ?? '',
        keysetId: json['keyset_id'] as String? ?? '',
        kemCiphertext: json['kem_ciphertext'] as String? ?? '',
        wrappedKey: json['wrapped_key'] as String? ?? '',
      );
}
