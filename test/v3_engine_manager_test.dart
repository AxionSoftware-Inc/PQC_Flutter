import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/features/crypto/v3/v3_engine_manager.dart';
import 'package:pqc_chat_app/features/crypto/v3/v3_engine_module.dart';
import 'package:pqc_chat_app/features/crypto/durability/crypto_durability_models.dart';
import 'package:pqc_chat_app/features/crypto/v3/v3_envelope.dart';

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

  test('v3 envelope round trips private and group prefixes', () {
    for (final isGroup in [false, true]) {
      final original = V3Envelope(
        isGroup: isGroup,
        messageId: 'message-1',
        senderDeviceId: 'device-1',
        keysetId: 'keyset-1',
        ciphertext: 'ciphertext',
        metadata: const {'kind': 'text'},
      );
      final decoded = V3Envelope.decode(original.encode());
      expect(decoded.isGroup, isGroup);
      expect(decoded.messageId, original.messageId);
      expect(decoded.metadata['kind'], 'text');
    }
  });
}
