import 'v3_protocol_contract.dart';

class V3Capabilities {
  const V3Capabilities({
    this.protocolVersion = V3ProtocolContract.protocolVersion,
    this.privatePrefix = V3ProtocolContract.privatePrefix,
    this.groupPrefix = V3ProtocolContract.groupPrefix,
    this.attachmentCipherVersion = V3ProtocolContract.attachmentCipherVersion,
  });

  final int protocolVersion;
  final String privatePrefix;
  final String groupPrefix;
  final String attachmentCipherVersion;

  Map<String, dynamic> toJson() => {
    'protocol_version': protocolVersion,
    'private_prefix': privatePrefix,
    'group_prefix': groupPrefix,
    'attachment_cipher_version': attachmentCipherVersion,
  };

  factory V3Capabilities.fromJson(Map<String, dynamic> json) {
    return V3Capabilities(
      protocolVersion: json['protocol_version'] as int? ?? 0,
      privatePrefix: json['private_prefix'] as String? ?? '',
      groupPrefix: json['group_prefix'] as String? ?? '',
      attachmentCipherVersion:
          json['attachment_cipher_version'] as String? ?? '',
    );
  }

  bool supportsPrivatePrefix(String prefix) => privatePrefix == prefix;
  bool supportsGroupPrefix(String prefix) => groupPrefix == prefix;
}
