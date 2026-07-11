import 'crypto_durability_models.dart';

class PayloadFormatRegistry {
  PayloadFormatRegistry({List<PayloadFormatDescriptor>? descriptors})
    : _descriptors =
          descriptors ??
          const [
            PayloadFormatDescriptor(
              formatId: 'pqc-private-v1',
              payloadKind: PayloadKind.privateMessage,
              prefix: 'pqc:v1:',
              introducedAtVersion: '1.0.0',
              decryptSupported: true,
              writeEnabled: true,
            ),
            PayloadFormatDescriptor(
              formatId: 'group-message-v1',
              payloadKind: PayloadKind.groupMessage,
              prefix: 'group:v1:',
              introducedAtVersion: '1.0.0',
              decryptSupported: true,
              writeEnabled: true,
            ),
            PayloadFormatDescriptor(
              formatId: 'group-envelope-pqc-v1',
              payloadKind: PayloadKind.groupEnvelope,
              prefix: 'group-wrap:pqc:v1:',
              introducedAtVersion: '1.0.0',
              decryptSupported: true,
            ),
          ];

  final List<PayloadFormatDescriptor> _descriptors;

  List<PayloadFormatDescriptor> get descriptors => List.unmodifiable(_descriptors);

  PayloadFormatDescriptor? describe(String payload) {
    for (final descriptor in _descriptors) {
      if (payload.startsWith(descriptor.prefix)) {
        return descriptor;
      }
    }
    return null;
  }
}
