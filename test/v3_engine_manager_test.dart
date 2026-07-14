import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/features/crypto/v3/v3_engine_manager.dart';
import 'package:pqc_chat_app/features/crypto/v3/v3_engine_module.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_durability_models.dart';

class _Encoder implements V3Encoder {
  @override
  String encode({
    required String plaintext,
    required Map<String, dynamic> context,
  }) => 'pqc:v3:$plaintext';
}

class _Decoder implements V3Decoder {
  @override
  Future<DecryptionOutcome> decode({
    required String payload,
    required Map<String, dynamic> context,
  }) {
    return Future.error(UnimplementedError());
  }
}

void main() {
  test('v3 writer stays disabled until explicit compatibility approval', () {
    final manager = V3EngineManager(
      module: V3EngineModule(
        formatId: 'pqc-v3-draft',
        privatePrefix: 'pqc:v3:',
        groupPrefix: 'group:v3:',
        encoder: _Encoder(),
        decoder: _Decoder(),
      ),
    );

    expect(manager.canWriteProduction, isFalse);
    expect(
      () => manager.encode(plaintext: 'hello', context: const {}),
      throwsStateError,
    );
    manager.openProductionWriteGate(approval: 'V3_COMPATIBILITY_APPROVED');
    expect(
      manager.encode(plaintext: 'hello', context: const {}),
      'pqc:v3:hello',
    );
  });
}
