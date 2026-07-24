import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_engine_flutter_adapter/pqc_engine_flutter_adapter.dart';

void main() {
  final context = ChatCryptoContext(
    currentUserId: 1,
    conversation: Conversation(
      id: 7,
      type: 'private',
      title: '',
      participantIds: const [1, 2],
      lastMessagePreview: '',
      updatedAt: DateTime.utc(2026),
    ),
    usersById: const {},
  );

  test('legacy mode does not execute SDK', () async {
    final legacy = _FakeAlgorithm(encrypted: 'legacy', decrypted: 'clear');
    final sdk = _FakeAlgorithm(encrypted: 'sdk', decrypted: 'sdk-clear');
    final algorithm = SdkV2MigrationAlgorithm(
      legacy: legacy,
      sdk: sdk,
      policy: const SdkV2MigrationPolicy(mode: SdkV2MigrationMode.legacy),
    );

    expect(await algorithm.encrypt(context: context, plaintext: 'x'), 'legacy');
    expect(
      await algorithm.decrypt(context: context, payload: 'pqc:v2:x'),
      'clear',
    );
    expect(legacy.encryptCalls, 1);
    expect(legacy.decryptCalls, 1);
    expect(sdk.encryptCalls, 0);
    expect(sdk.decryptCalls, 0);
  });

  test('shadow mode reports mismatch but preserves legacy result', () async {
    final reports = <SdkV2ShadowReport>[];
    final legacy = _FakeAlgorithm(encrypted: 'legacy', decrypted: 'clear');
    final sdk = _FakeAlgorithm(encrypted: 'sdk', decrypted: '[decrypt-error]');
    final algorithm = SdkV2MigrationAlgorithm(
      legacy: legacy,
      sdk: sdk,
      policy: const SdkV2MigrationPolicy(mode: SdkV2MigrationMode.shadow),
      onShadowReport: reports.add,
    );

    expect(
      await algorithm.decrypt(context: context, payload: 'pqc:v2:x'),
      'clear',
    );
    expect(reports, hasLength(1));
    expect(reports.single.matches, isFalse);
    expect(reports.single.legacyCategory, SdkV2ResultCategory.success);
    expect(reports.single.sdkCategory, SdkV2ResultCategory.decryptError);
  });

  test('read mode uses SDK decoder and legacy writer', () async {
    final legacy = _FakeAlgorithm(encrypted: 'legacy', decrypted: 'old');
    final sdk = _FakeAlgorithm(encrypted: 'sdk', decrypted: 'new');
    final algorithm = SdkV2MigrationAlgorithm(
      legacy: legacy,
      sdk: sdk,
      policy: const SdkV2MigrationPolicy(mode: SdkV2MigrationMode.sdkRead),
    );

    expect(await algorithm.encrypt(context: context, plaintext: 'x'), 'legacy');
    expect(
      await algorithm.decrypt(context: context, payload: 'pqc:v2:x'),
      'new',
    );
  });

  test('active writer requires an explicit second gate', () {
    expect(() => SdkV2MigrationPolicy.fromEnvironment(), returnsNormally);
    const blocked = SdkV2MigrationPolicy(
      mode: SdkV2MigrationMode.sdkActive,
      writerGateEnabled: true,
    );
    expect(blocked.usesSdkWriter, isFalse);
  });

  test('health monitor records only non-secret comparison counters', () {
    final monitor = SdkV2MigrationHealthMonitor()
      ..record(
        const SdkV2ShadowReport(
          conversationId: 1,
          isGroup: false,
          matches: true,
          legacyCategory: SdkV2ResultCategory.success,
          sdkCategory: SdkV2ResultCategory.success,
        ),
      )
      ..record(
        const SdkV2ShadowReport(
          conversationId: 2,
          isGroup: true,
          matches: false,
          legacyCategory: SdkV2ResultCategory.success,
          sdkCategory: SdkV2ResultCategory.recoveryPending,
        ),
      );

    expect(monitor.snapshot.comparisons, 2);
    expect(monitor.snapshot.matches, 1);
    expect(monitor.snapshot.mismatches, 1);
    expect(monitor.snapshot.groupMismatches, 1);
    expect(monitor.snapshot.isCompatible, isFalse);
  });

  test('routing disagreement fails closed', () {
    final algorithm = SdkV2MigrationAlgorithm(
      legacy: _FakeAlgorithm(encrypted: '', decrypted: '', supports: true),
      sdk: _FakeAlgorithm(encrypted: '', decrypted: '', supports: false),
      policy: const SdkV2MigrationPolicy(mode: SdkV2MigrationMode.legacy),
    );
    expect(
      () => algorithm.supportsConversation(context.conversation),
      throwsStateError,
    );
  });
}

class _FakeAlgorithm implements ChatCipherAlgorithm {
  _FakeAlgorithm({
    required this.encrypted,
    required this.decrypted,
    this.supports = true,
  });

  final String encrypted;
  final String decrypted;
  final bool supports;
  int encryptCalls = 0;
  int decryptCalls = 0;

  @override
  bool canDecrypt(String payload) => supports;

  @override
  bool supportsConversation(Conversation conversation) => supports;

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    decryptCalls++;
    return decrypted;
  }

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    encryptCalls++;
    return encrypted;
  }
}
