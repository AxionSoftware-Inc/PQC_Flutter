/// Draft v3 wire contract.
///
/// This file is intentionally separate from the frozen v2 contract. No v3
/// payload is emitted until the codec, vectors, migration tests and server
/// negotiation are complete.
abstract final class V3ProtocolContract {
  static const protocolVersion = 3;
  static const privatePrefix = 'pqc:v3';
  static const groupPrefix = 'group:v3';
  static const attachmentCipherVersion = 'attachment:v3';
}
