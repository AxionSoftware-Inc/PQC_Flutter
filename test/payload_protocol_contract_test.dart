import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/features/crypto/durability/payload_format_registry.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_durability_models.dart';
import 'package:pqc_chat_app/features/crypto/durability/protocol_version_manager.dart';

void main() {
  test(
    'protocol registry keeps historical readers and exactly one v2 writer',
    () {
      final registry = PayloadFormatRegistry();

      expect(registry.describe('pqc:v1:historical'), isNull);
      expect(registry.describe('group:v1:historical'), isNull);
      expect(registry.describe('pqc:v2:current'), isNotNull);
      expect(registry.describe('group:v2:current'), isNotNull);

      expect(
        registry
            .writersFor(PayloadKind.privateMessage)
            .map((item) => item.prefix),
        ['pqc:v2:'],
      );
      expect(
        registry
            .writersFor(PayloadKind.groupMessage)
            .map((item) => item.prefix),
        ['group:v2:'],
      );
    },
  );

  test('retired writer remains a decoder and cannot become an encoder', () {
    final manager = ProtocolVersionManager(
      registry: PayloadFormatRegistry(
        descriptors: const [
          PayloadFormatDescriptor(
            formatId: 'private-v2',
            payloadKind: PayloadKind.privateMessage,
            prefix: 'pqc:v2:',
            introducedAtVersion: '2.0.0',
            decryptSupported: true,
            writeEnabled: false,
          ),
          PayloadFormatDescriptor(
            formatId: 'private-v3',
            payloadKind: PayloadKind.privateMessage,
            prefix: 'pqc:v3:',
            introducedAtVersion: '3.0.0',
            decryptSupported: true,
            writeEnabled: true,
          ),
          PayloadFormatDescriptor(
            formatId: 'group-v2',
            payloadKind: PayloadKind.groupMessage,
            prefix: 'group:v2:',
            introducedAtVersion: '2.0.0',
            decryptSupported: true,
            writeEnabled: true,
          ),
        ],
      ),
    );

    expect(
      manager.activeWriter(PayloadKind.privateMessage).formatId,
      'private-v3',
    );
    expect(manager.canDecode('pqc:v2:old-message'), isTrue);
    expect(manager.readers(PayloadKind.privateMessage), hasLength(2));
  });
}
