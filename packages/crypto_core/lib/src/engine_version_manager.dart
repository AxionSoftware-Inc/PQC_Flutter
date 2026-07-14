import 'crypto/durability/crypto_durability_models.dart';
import 'crypto/durability/payload_format_registry.dart';

/// Release metadata is separate from the wire protocol version.
class EngineReleaseDescriptor {
  const EngineReleaseDescriptor({
    required this.releaseId,
    required this.activeProtocolVersion,
    this.readsHistoricalFormats = true,
  });

  final String releaseId;
  final String activeProtocolVersion;
  final bool readsHistoricalFormats;
}

class EngineVersionManager {
  EngineVersionManager({
    PayloadFormatRegistry? payloadRegistry,
    EngineReleaseDescriptor? release,
  }) : payloadRegistry = payloadRegistry ?? PayloadFormatRegistry(),
       release =
           release ??
           const EngineReleaseDescriptor(
             releaseId: '2.5.0',
             activeProtocolVersion: '2',
           );

  final PayloadFormatRegistry payloadRegistry;
  final EngineReleaseDescriptor release;

  String get activeEngineVersion => release.releaseId;

  List<PayloadFormatDescriptor> get readableFormats => payloadRegistry
      .descriptors
      .where((item) => item.decryptSupported)
      .toList(growable: false);

  PayloadFormatDescriptor? describe(String payload) =>
      payloadRegistry.describe(payload);

  bool canRead(String payload) => describe(payload)?.decryptSupported == true;

  String activeWriterPrefix({required bool isGroup}) {
    final writers = payloadRegistry.writersFor(
      isGroup ? PayloadKind.groupMessage : PayloadKind.privateMessage,
    );
    if (writers.length != 1) {
      throw StateError(
        'Exactly one active writer is required for this engine.',
      );
    }
    return writers.single.prefix;
  }

  void validate() {
    activeWriterPrefix(isGroup: false);
    activeWriterPrefix(isGroup: true);
    if (!release.readsHistoricalFormats && readableFormats.length > 1) {
      throw StateError(
        'Historical readers must be explicitly enabled for this release.',
      );
    }
  }
}
