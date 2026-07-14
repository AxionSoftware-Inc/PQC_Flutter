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
  });

  final bool isGroup;
  final String messageId;
  final String senderDeviceId;
  final String keysetId;
  final String ciphertext;
  final Map<String, dynamic> metadata;

  String get prefix => isGroup
      ? V3ProtocolContract.groupPrefix
      : V3ProtocolContract.privatePrefix;

  Map<String, dynamic> toJson() => {
    'protocol_version': V3ProtocolContract.protocolVersion,
    'message_id': messageId,
    'sender_device_id': senderDeviceId,
    'keyset_id': keysetId,
    'ciphertext': ciphertext,
    'metadata': metadata,
  };

  String encode() =>
      '$prefix:${base64UrlEncode(utf8.encode(jsonEncode(toJson())))}';

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
    );
  }
}
