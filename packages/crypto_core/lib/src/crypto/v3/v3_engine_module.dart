import '../durability/crypto_durability_models.dart';

/// Dependency-inverted v3 module boundary. Crypto implementations, storage,
/// transport and policy are supplied by adapters; the manager never imports
/// HTTP, Flutter, database or device APIs.
abstract interface class V3Encoder {
  String encode({
    required String plaintext,
    required Map<String, dynamic> context,
  });
}

abstract interface class V3Decoder {
  Future<DecryptionOutcome> decode({
    required String payload,
    required Map<String, dynamic> context,
  });
}

class V3EngineModule {
  const V3EngineModule({
    required this.formatId,
    required this.privatePrefix,
    required this.groupPrefix,
    required this.encoder,
    required this.decoder,
  });

  final String formatId;
  final String privatePrefix;
  final String groupPrefix;
  final V3Encoder encoder;
  final V3Decoder decoder;
}
