import 'package:crypto_core/antiq_protocol_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

class _Encoder implements V3Encoder {
  @override
  Future<String> encode({
    required String plaintext,
    required Map<String, dynamic> context,
  }) async => 'pqc:v3:$plaintext';
}

class _Decoder implements V3Decoder {
  @override
  Future<DecryptionOutcome> decode({
    required String payload,
    required Map<String, dynamic> context,
  }) async => DecryptFormatUnsupported(payload: payload);
}

void main() {
  test(
    'v2.5 keeps v2 messages and selects a dedicated group envelope writer',
    () {
      final sdk = AntiQProtocolSdk.v25();

      expect(sdk.release.releaseId, '2.5.0');
      expect(sdk.release.wireProtocol, 'v2');
      expect(
        sdk.activeWriterPrefix(kind: PayloadKind.privateMessage),
        'pqc:v2:',
      );
      expect(
        sdk.activeWriterPrefix(kind: PayloadKind.groupEnvelope),
        'group-wrap:pqc:v2.5:',
      );
      expect(sdk.canDecode('pqc:v2:historical'), isTrue);
      expect(sdk.canDecode('pqc:v3:newer'), isTrue);
    },
  );

  test('v3 writer needs an explicit approval after capability negotiation', () {
    final sdk = AntiQProtocolSdk.v3(
      module: V3EngineModule(
        formatId: 'v3-test',
        privatePrefix: 'pqc:v3:',
        groupPrefix: 'group:v3:',
        encoder: _Encoder(),
        decoder: _Decoder(),
      ),
    );

    expect(sdk.release.wireProtocol, 'v3');
    expect(sdk.activeWriterPrefix(kind: PayloadKind.groupMessage), 'group:v3:');
    expect(sdk.negotiateV3(const V3Capabilities()), isTrue);
    expect(sdk.v3!.canWriteProduction, isFalse);
    sdk.approveV3Writer();
    expect(sdk.v3!.canWriteProduction, isTrue);
  });
}
