import 'crypto_durability_models.dart';
import 'v2_protocol_contract.dart';

class PayloadFormatRegistry {
  PayloadFormatRegistry({List<PayloadFormatDescriptor>? descriptors})
    : _descriptors =
          descriptors ??
          const [
            PayloadFormatDescriptor(
              formatId: 'pqc-private-v2',
              payloadKind: PayloadKind.privateMessage,
              prefix: '${PqcV2ProtocolContract.privatePrefix}:',
              introducedAtVersion: '2.0.0',
              decryptSupported: true,
              writeEnabled: true,
            ),
            PayloadFormatDescriptor(
              formatId: 'group-message-v2',
              payloadKind: PayloadKind.groupMessage,
              prefix: '${PqcV2ProtocolContract.groupPrefix}:',
              introducedAtVersion: '2.0.0',
              decryptSupported: true,
              writeEnabled: true,
            ),
            PayloadFormatDescriptor(
              formatId: 'group-envelope-pqc-v2',
              payloadKind: PayloadKind.groupEnvelope,
              prefix: '${PqcV2ProtocolContract.groupWrapPrefix}:',
              introducedAtVersion: '2.0.0',
              decryptSupported: true,
            ),
          ];

  final List<PayloadFormatDescriptor> _descriptors;

  List<PayloadFormatDescriptor> get descriptors =>
      List.unmodifiable(_descriptors);

  PayloadFormatDescriptor? describe(String payload) {
    for (final descriptor in _descriptors) {
      if (payload.startsWith(descriptor.prefix)) {
        return descriptor;
      }
    }
    return null;
  }

  /// The only formats this client is allowed to create.  Keep this separate
  /// from [describe]: a readable historical format must never become a writer
  /// merely because its decoder is registered.
  List<PayloadFormatDescriptor> writersFor(PayloadKind kind) => _descriptors
      .where((item) => item.payloadKind == kind && item.writeEnabled)
      .toList(growable: false);

  bool supportsWriterPrefix(String prefix) =>
      _descriptors.any((item) => item.prefix == prefix && item.writeEnabled);
}
