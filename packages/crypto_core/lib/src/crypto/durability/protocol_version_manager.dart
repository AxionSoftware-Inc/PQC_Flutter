import 'crypto_durability_models.dart';
import 'payload_format_registry.dart';

/// Owns protocol compatibility policy.
///
/// A protocol format is immutable once released. A future engine adds a new
/// descriptor with [writeEnabled] true and keeps every historical descriptor
/// with [decryptSupported] true. Retiring an encoder must never remove its
/// decoder. v2 and v2.5 intentionally share the same v2 descriptor because
/// they have the same wire format.
class ProtocolVersionManager {
  ProtocolVersionManager({PayloadFormatRegistry? registry})
    : registry = registry ?? PayloadFormatRegistry() {
    _validate();
  }

  final PayloadFormatRegistry registry;

  List<PayloadFormatDescriptor> get formats => registry.descriptors;

  PayloadFormatDescriptor activeWriter(PayloadKind kind) {
    final writers = registry.writersFor(kind);
    if (writers.length != 1) {
      throw StateError(
        'Protocol configuration must have exactly one writer for $kind; '
        'found ${writers.length}.',
      );
    }
    return writers.single;
  }

  List<PayloadFormatDescriptor> readers(PayloadKind kind) =>
      registry.readersFor(kind);

  PayloadFormatDescriptor? readerForPayload(String payload) =>
      registry.describe(payload);

  bool canDecode(String payload) => readerForPayload(payload) != null;

  /// Validates the registry at startup so a release cannot silently ship with
  /// two encoders or with a format that is neither readable nor writable.
  void _validate() {
    final ids = <String>{};
    final prefixes = <String>{};
    for (final format in formats) {
      if (format.formatId.trim().isEmpty || !ids.add(format.formatId)) {
        throw StateError('Duplicate or empty protocol format id.');
      }
      if (format.prefix.trim().isEmpty || !prefixes.add(format.prefix)) {
        throw StateError('Duplicate or empty protocol prefix.');
      }
      if (!format.decryptSupported && !format.writeEnabled) {
        throw StateError(
          'Format ${format.formatId} has neither a decoder nor an encoder.',
        );
      }
    }
    activeWriter(PayloadKind.privateMessage);
    activeWriter(PayloadKind.groupMessage);
  }
}
