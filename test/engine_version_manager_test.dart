import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v2.5 writes frozen v2 and reads historical formats', () {
    final manager = EngineVersionManager();
    expect(manager.activeEngineVersion, '2.5.0');
    expect(manager.release.activeProtocolVersion, '2');
    expect(manager.canRead('pqc:v2:payload'), isTrue);
    expect(manager.canRead('group:v2:payload'), isTrue);
    expect(manager.activeWriterPrefix(isGroup: false), 'pqc:v2:');
    expect(manager.activeWriterPrefix(isGroup: true), 'group:v2:');
    expect(() => manager.validate(), returnsNormally);
  });
}
