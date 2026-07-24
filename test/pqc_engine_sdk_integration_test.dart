import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_engine_flutter_adapter/pqc_engine_flutter_adapter.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';

void main() {
  test('frozen V2 app resolves the standalone SDK contract', () {
    final engine = PqcV2Engine();

    expect(engine.engineId, 'pqc-v2');
    expect(engine.protocolVersion, 2);
    expect(engine.privatePrefix, 'pqc:v2');
    expect(engine.groupPrefix, 'group:v2');
    expect(engine.attachmentCipherVersions, contains('attachment:v2'));
    const policy = SdkV2MigrationPolicy(mode: SdkV2MigrationMode.legacy);
    expect(policy.usesSdkReader, isFalse);
    expect(policy.usesSdkWriter, isFalse);
  });
}
