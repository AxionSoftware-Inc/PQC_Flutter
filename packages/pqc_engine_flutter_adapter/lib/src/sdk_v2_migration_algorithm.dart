import 'package:crypto_core/crypto_core.dart';

import 'sdk_v2_migration_policy.dart';

class SdkV2MigrationAlgorithm implements ChatCipherAlgorithm {
  const SdkV2MigrationAlgorithm({
    required this.legacy,
    required this.sdk,
    required this.policy,
    this.onShadowReport,
  });

  final ChatCipherAlgorithm legacy;
  final ChatCipherAlgorithm sdk;
  final SdkV2MigrationPolicy policy;
  final SdkV2ShadowReporter? onShadowReport;

  @override
  bool supportsConversation(Conversation conversation) {
    final legacySupports = legacy.supportsConversation(conversation);
    final sdkSupports = sdk.supportsConversation(conversation);
    if (legacySupports != sdkSupports) {
      throw StateError('Legacy and SDK conversation routing disagree.');
    }
    return sdkSupports;
  }

  @override
  bool canDecrypt(String payload) {
    final legacySupports = legacy.canDecrypt(payload);
    final sdkSupports = sdk.canDecrypt(payload);
    if (legacySupports != sdkSupports) {
      throw StateError('Legacy and SDK payload routing disagree.');
    }
    return sdkSupports;
  }

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) {
    final selected = policy.usesSdkWriter ? sdk : legacy;
    return selected.encrypt(context: context, plaintext: plaintext);
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    if (policy.usesSdkReader) {
      return sdk.decrypt(context: context, payload: payload);
    }
    final legacyResult = await legacy.decrypt(
      context: context,
      payload: payload,
    );
    if (!policy.comparesShadow) {
      return legacyResult;
    }
    final sdkResult = await sdk.decrypt(context: context, payload: payload);
    onShadowReport?.call(
      SdkV2ShadowReport(
        conversationId: context.conversation.id,
        isGroup: context.conversation.isGroup,
        matches: legacyResult == sdkResult,
        legacyCategory: _category(legacyResult),
        sdkCategory: _category(sdkResult),
      ),
    );
    return legacyResult;
  }
}

SdkV2ResultCategory _category(String result) {
  return switch (result) {
    '[history-unavailable]' => SdkV2ResultCategory.historyUnavailable,
    '[history-recovery-pending]' => SdkV2ResultCategory.recoveryPending,
    '[decrypt-error]' => SdkV2ResultCategory.decryptError,
    _ => SdkV2ResultCategory.success,
  };
}
