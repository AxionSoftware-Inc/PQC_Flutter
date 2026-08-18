import '../crypto/durability/crypto_durability_models.dart';
import '../crypto/durability/payload_format_registry.dart';
import '../crypto/durability/protocol_version_manager.dart';
import '../crypto/durability/v2_protocol_contract.dart';
import '../crypto/v3/v3_capabilities.dart';
import '../crypto/v3/v3_engine_manager.dart';
import '../crypto/v3/v3_engine_module.dart';

/// Stable release metadata exposed to SDK consumers.
///
/// `releaseId` identifies the product/engine release; `wireProtocol` is the
/// immutable network format. V2.5 deliberately retains `v2`.
class AntiQEngineRelease {
  const AntiQEngineRelease({
    required this.releaseId,
    required this.wireProtocol,
    required this.writerProfile,
  });

  final String releaseId;
  final String wireProtocol;
  final PayloadWriteProfile writerProfile;

  static const v2 = AntiQEngineRelease(
    releaseId: '2.0.0',
    wireProtocol: 'v2',
    writerProfile: PayloadWriteProfile.v2,
  );

  static const v25 = AntiQEngineRelease(
    releaseId: '2.5.0',
    wireProtocol: 'v2',
    writerProfile: PayloadWriteProfile.v25,
  );

  static const v3 = AntiQEngineRelease(
    releaseId: '3.0.0',
    wireProtocol: 'v3',
    writerProfile: PayloadWriteProfile.v3,
  );
}

/// Platform-independent protocol entry point for V2, V2.5 and V3.
///
/// Storage, HTTP, account login and Flutter UI deliberately do not appear in
/// this API. Hosts inject those concerns around the SDK.
class AntiQProtocolSdk {
  AntiQProtocolSdk._({required this.release, required this.protocols, this.v3});

  factory AntiQProtocolSdk.v2() => AntiQProtocolSdk._(
    release: AntiQEngineRelease.v2,
    protocols: ProtocolVersionManager(
      registry: PayloadFormatRegistry(writeProfile: PayloadWriteProfile.v2),
    ),
  );

  factory AntiQProtocolSdk.v25() => AntiQProtocolSdk._(
    release: AntiQEngineRelease.v25,
    protocols: ProtocolVersionManager(
      registry: PayloadFormatRegistry(writeProfile: PayloadWriteProfile.v25),
    ),
  );

  factory AntiQProtocolSdk.v3({required V3EngineModule module}) {
    return AntiQProtocolSdk._(
      release: AntiQEngineRelease.v3,
      protocols: ProtocolVersionManager(
        registry: PayloadFormatRegistry(writeProfile: PayloadWriteProfile.v3),
      ),
      v3: V3EngineManager(module: module),
    );
  }

  final AntiQEngineRelease release;
  final ProtocolVersionManager protocols;
  final V3EngineManager? v3;

  String activeWriterPrefix({required PayloadKind kind}) =>
      protocols.activeWriter(kind).prefix;

  bool canDecode(String payload) => protocols.canDecode(payload);

  bool supportsV2History(String payload) =>
      PqcV2ProtocolContract.isPrivatePayload(payload) ||
      PqcV2ProtocolContract.isGroupPayload(payload);

  bool negotiateV3(V3Capabilities capabilities) {
    final manager = v3;
    return manager != null && manager.negotiate(capabilities);
  }

  void approveV3Writer() {
    final manager = v3;
    if (manager == null) {
      throw StateError('The selected SDK release has no V3 writer.');
    }
    manager.openProductionWriteGate(approval: 'V3_COMPATIBILITY_APPROVED');
  }
}
