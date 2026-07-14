/// Read-only bridge for the frozen v2 engine. The callbacks are injected by
/// the composition root, so this module cannot create v2 payloads.
class V2CompatibilityDecoder {
  const V2CompatibilityDecoder({
    required this.privateDecoder,
    required this.groupDecoder,
  });

  final Future<String> Function(String payload) privateDecoder;
  final Future<String> Function(String payload) groupDecoder;

  bool canDecode(String payload) =>
      payload.startsWith('${V2ProtocolPrefixes.privatePrefix}:') ||
      payload.startsWith('${V2ProtocolPrefixes.groupPrefix}:');

  Future<String> decode(String payload) {
    if (payload.startsWith('${V2ProtocolPrefixes.privatePrefix}:')) {
      return privateDecoder(payload);
    }
    if (payload.startsWith('${V2ProtocolPrefixes.groupPrefix}:')) {
      return groupDecoder(payload);
    }
    throw const FormatException('Payload is not a supported v2 format.');
  }
}

abstract final class V2ProtocolPrefixes {
  static const privatePrefix = 'pqc:v2';
  static const groupPrefix = 'group:v2';
}
