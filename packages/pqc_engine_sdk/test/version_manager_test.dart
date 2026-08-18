import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('shared release catalog keeps protocol capabilities monotonic', () {
    expect(PqcProtocolRelease.v2.supportedProtocolIds, ['v2']);
    expect(PqcProtocolRelease.v25.supportedProtocolIds, ['v2', 'v2.5']);
    expect(PqcProtocolRelease.tryParse('3.0.0')?.supportedProtocolIds, [
      'v2',
      'v2.5',
      'v3',
    ]);
  });

  final engine = PqcV2Engine();
  final capabilities = PqcRemoteCapabilities(
    privateReadPrefixes: {PqcV2Wire.privatePrefix},
    groupReadPrefixes: {PqcV2Wire.groupPrefix},
    privateWritePrefixes: {PqcV2Wire.privatePrefix},
    groupWritePrefixes: {PqcV2Wire.groupPrefix},
    attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
    minimumDecoderVersion: 2,
    groupEnvelopeReadPrefixes: {PqcV2Wire.groupWrapPrefix},
    groupEnvelopeWritePrefixes: {PqcV2Wire.groupWrapPrefix},
  );

  test('writer is closed unless explicitly enabled', () {
    final manager = PqcEngineManager(
      decoders: [engine],
      activeWriterId: engine.engineId,
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: capabilities,
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
  });

  test('capability gate allows only advertised format', () {
    final manager = PqcEngineManager(
      decoders: [engine],
      activeWriterId: engine.engineId,
      writerEnabled: true,
    );
    expect(
      manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: capabilities,
      ),
      same(engine),
    );
    expect(
      manager.requireWriter(
        kind: PqcConversationKind.groupEnvelope,
        remote: capabilities,
      ),
      same(engine),
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.group,
        remote: PqcRemoteCapabilities(
          privateReadPrefixes: {PqcV2Wire.privatePrefix},
          groupReadPrefixes: {},
          privateWritePrefixes: {PqcV2Wire.privatePrefix},
          groupWritePrefixes: {},
          attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
          minimumDecoderVersion: 2,
        ),
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
  });

  test('v2.5 envelope writer requires explicit server capability', () {
    final v25 = PqcV2Engine(enableV25GroupEnvelopeWriter: true);
    final manager = PqcEngineManager(
      decoders: [v25],
      activeWriterId: v25.engineId,
      writerEnabled: true,
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.groupEnvelope,
        remote: capabilities,
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
    final v25Capabilities = PqcRemoteCapabilities(
      privateReadPrefixes: {PqcV2Wire.privatePrefix},
      groupReadPrefixes: {PqcV2Wire.groupPrefix},
      privateWritePrefixes: {PqcV2Wire.privatePrefix},
      groupWritePrefixes: {PqcV2Wire.groupPrefix},
      attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
      minimumDecoderVersion: 2,
      groupEnvelopeReadPrefixes: {PqcV2Wire.groupWrapV25Prefix},
      groupEnvelopeWritePrefixes: {PqcV2Wire.groupWrapV25Prefix},
    );
    expect(
      manager.requireWriter(
        kind: PqcConversationKind.groupEnvelope,
        remote: v25Capabilities,
      ),
      same(v25),
    );
  });

  test('V3 can be registered beside V2 without prefix ambiguity', () {
    final v2 = PqcV2Engine();
    final v3 = PqcV3Engine();
    final manager = PqcEngineManager(
      decoders: [v2, v3],
      activeWriterId: v3.engineId,
      writerEnabled: true,
    );
    final capabilities = PqcRemoteCapabilities(
      privateReadPrefixes: {PqcV2Wire.privatePrefix, PqcV3Wire.privatePrefix},
      groupReadPrefixes: {PqcV2Wire.groupPrefix, PqcV3Wire.groupPrefix},
      privateWritePrefixes: {PqcV3Wire.privatePrefix},
      groupWritePrefixes: {PqcV3Wire.groupPrefix},
      attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
      minimumDecoderVersion: 3,
      groupEnvelopeReadPrefixes: {PqcV2Wire.groupWrapPrefix},
      groupEnvelopeWritePrefixes: {PqcV2Wire.groupWrapPrefix},
    );
    expect(
      manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: capabilities,
      ),
      same(v3),
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: capabilities,
        hasAttachments: true,
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
    expect(
      manager.resolveDecoder(
        kind: PqcConversationKind.private,
        payload: '${PqcV3Wire.privatePrefix}:payload',
      ),
      same(v3),
    );
  });

  test('rejects read/write asymmetry and decoder downgrade', () {
    final manager = PqcEngineManager(
      decoders: [engine],
      activeWriterId: engine.engineId,
      writerEnabled: true,
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: PqcRemoteCapabilities(
          privateReadPrefixes: {},
          groupReadPrefixes: {PqcV2Wire.groupPrefix},
          privateWritePrefixes: {PqcV2Wire.privatePrefix},
          groupWritePrefixes: {PqcV2Wire.groupPrefix},
          attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
          minimumDecoderVersion: 2,
        ),
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
    expect(
      () => manager.requireWriter(
        kind: PqcConversationKind.private,
        remote: PqcRemoteCapabilities(
          privateReadPrefixes: {PqcV2Wire.privatePrefix},
          groupReadPrefixes: {PqcV2Wire.groupPrefix},
          privateWritePrefixes: {PqcV2Wire.privatePrefix},
          groupWritePrefixes: {PqcV2Wire.groupPrefix},
          attachmentCipherVersions: {PqcV2Wire.attachmentCipherVersion},
          minimumDecoderVersion: 3,
        ),
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
  });

  test('routes recognized formats and rejects unknown payloads', () {
    final manager = PqcEngineManager(decoders: [engine]);
    expect(
      manager.resolveDecoder(
        kind: PqcConversationKind.private,
        payload: '${PqcV2Wire.privatePrefix}:payload',
      ),
      same(engine),
    );
    expect(
      manager.resolveDecoder(
        kind: PqcConversationKind.groupEnvelope,
        payload: '${PqcV2Wire.groupWrapV25Prefix}:payload',
      ),
      same(engine),
    );
    expect(
      () => manager.resolveDecoder(
        kind: PqcConversationKind.private,
        payload: 'pqc:v99:payload',
      ),
      throwsA(isA<PqcCompatibilityException>()),
    );
  });

  test('rejects duplicate engine ids', () {
    expect(
      () => PqcEngineManager(decoders: [engine, PqcV2Engine()]),
      throwsArgumentError,
    );
  });

  test('normalizes backend capability JSON and protects its sets', () {
    final parsed = PqcRemoteCapabilities.fromJson({
      'readable_private_message_prefixes': ['pqc:v2:'],
      'readable_group_message_prefixes': ['group:v2:'],
      'private_message_prefixes': ['pqc:v2:'],
      'group_message_prefixes': ['group:v2:'],
      'readable_group_envelope_prefixes': ['group-wrap:pqc:v2:'],
      'group_envelope_prefixes': ['group-wrap:pqc:v2:'],
      'attachment_cipher_versions': ['attachment:v2'],
      'minimum_decoder_version': '2.0.0',
    });
    expect(parsed.minimumDecoderVersion, 2);
    expect(parsed.privateReadPrefixes, contains('pqc:v2'));
    expect(parsed.groupEnvelopeReadPrefixes, contains('group-wrap:pqc:v2'));
    expect(
      () => parsed.privateReadPrefixes.add('pqc:v3:'),
      throwsUnsupportedError,
    );
  });

  test('accepts a single-use decoder iterable', () {
    Iterable<PqcEngine> oneShot() sync* {
      yield engine;
    }

    final manager = PqcEngineManager(decoders: oneShot());
    expect(manager.decoders, hasLength(1));
  });
}
