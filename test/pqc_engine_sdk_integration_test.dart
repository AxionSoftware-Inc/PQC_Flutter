import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';

void main() {
  test('frozen V2 app resolves the standalone SDK contract', () {
    final engine = PqcV2Engine();

    expect(engine.engineId, 'pqc-v2');
    expect(engine.protocolVersion, 2);
    expect(engine.privatePrefix, 'pqc:v2');
    expect(engine.groupPrefix, 'group:v2');
    expect(
      engine.attachmentCipherVersions,
      contains('attachment:v2'),
    );
  });
}
