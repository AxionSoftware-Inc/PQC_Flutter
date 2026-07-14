/// Frozen PQCv2 wire contract. Changes here require a new protocol version.
abstract final class PqcV2ProtocolContract {
  static const protocolVersion = 2;
  static const privatePrefix = 'pqc:v2';
  static const groupPrefix = 'group:v2';
  static const groupWrapPrefix = 'group-wrap:pqc:v2';
  static const privateAlgorithm = 'ml-kem-768+a256gcm+ml-dsa-65';
  static const groupAlgorithm = 'a256gcm+group-ml-kem-768';
  static const groupEnvelopeAlgorithm = 'group-ml-kem-768-aesgcm-v2';
  static const attachmentCipherVersion = 'attachment:v2';
  static const backupSchema = 'enterprise-recovery-manifest';
  static const backupSchemaRevision = 2;

  static bool isPrivatePayload(String value) =>
      value.startsWith('$privatePrefix:');

  static bool isGroupPayload(String value) => value.startsWith('$groupPrefix:');
}
