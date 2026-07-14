import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/features/crypto/durability/payload_format_registry.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_durability_models.dart';

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
}
