import 'package:crypto_core/crypto_core.dart';
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
  }) {
    return Future.error(UnimplementedError());
  }
}

void main() {
  test(
    'v3 writer stays disabled until explicit compatibility approval',
    () async {
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
        await manager.encode(plaintext: 'hello', context: const {}),
        'pqc:v3:hello',
      );
    },
  );

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

  test('v3 associated data is deterministic and conversation-bound', () {
    final first = PqcV3CryptoAdapter.associatedData(
      conversationId: 4,
      conversationType: 'private',
      messageId: 'm1',
      senderDeviceId: 'd1',
      keysetId: 'k1',
    );
    final second = PqcV3CryptoAdapter.associatedData(
      conversationId: 4,
      conversationType: 'private',
      messageId: 'm1',
      senderDeviceId: 'd1',
      keysetId: 'k1',
    );
    final changed = PqcV3CryptoAdapter.associatedData(
      conversationId: 5,
      conversationType: 'private',
      messageId: 'm1',
      senderDeviceId: 'd1',
      keysetId: 'k1',
    );
    expect(first, second);
    expect(first, isNot(changed));
  });

  test('v3 keyset binding covers both public keys without changing V2 id', () {
    const device = AppUserDevice(
      deviceId: 'device-1',
      keysetId: 'legacy-v2-id',
      deviceName: 'test',
      platform: 'test',
      identityPublicKey: '',
      keyAlgorithm: '',
      pqcPublicKey: 'kem-public-key',
      pqcSigningPublicKey: 'signing-public-key',
    );
    const sameKeys = AppUserDevice(
      deviceId: 'device-1',
      keysetId: 'different-legacy-id',
      deviceName: 'test',
      platform: 'test',
      identityPublicKey: '',
      keyAlgorithm: '',
      pqcPublicKey: 'kem-public-key',
      pqcSigningPublicKey: 'signing-public-key',
    );
    const changedSigningKey = AppUserDevice(
      deviceId: 'device-1',
      keysetId: 'legacy-v2-id',
      deviceName: 'test',
      platform: 'test',
      identityPublicKey: '',
      keyAlgorithm: '',
      pqcPublicKey: 'kem-public-key',
      pqcSigningPublicKey: 'different-signing-key',
    );

    expect(device.keysetId, 'legacy-v2-id');
    expect(device.v3KeysetId, same(sameKeys.v3KeysetId));
    expect(device.v3KeysetId, isNot(device.keysetId));
    expect(device.v3KeysetId, isNot(changedSigningKey.v3KeysetId));
  });

  test('v3 negotiation rejects downgrade and missing group support', () {
    final manager = V3EngineManager(
      module: V3EngineModule(
        formatId: 'v3',
        privatePrefix: 'pqc:v3:',
        groupPrefix: 'group:v3:',
        encoder: _Encoder(),
        decoder: _Decoder(),
      ),
    );
    expect(manager.negotiate(const V3Capabilities()), isTrue);
    expect(
      manager.negotiate(const V3Capabilities(protocolVersion: 2)),
      isFalse,
    );
    expect(
      manager.negotiate(const V3Capabilities(groupPrefix: 'group:v2')),
      isFalse,
    );
  });
}
