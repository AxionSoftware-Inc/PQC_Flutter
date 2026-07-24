enum SdkV2MigrationMode { legacy, shadow, sdkRead, sdkActive }

class SdkV2MigrationPolicy {
  const SdkV2MigrationPolicy({
    required this.mode,
    this.writerGateEnabled = false,
    this.compatibilityApproved = false,
  });

  factory SdkV2MigrationPolicy.fromEnvironment() {
    const rawMode = String.fromEnvironment(
      'SDK_V2_MODE',
      defaultValue: 'legacy',
    );
    const writerEnabled = bool.fromEnvironment(
      'SDK_V2_WRITER_ENABLED',
      defaultValue: false,
    );
    const compatibilityApproved = bool.fromEnvironment(
      'SDK_V2_COMPATIBILITY_APPROVED',
      defaultValue: false,
    );
    final mode = switch (rawMode) {
      'legacy' => SdkV2MigrationMode.legacy,
      'shadow' => SdkV2MigrationMode.shadow,
      'read' => SdkV2MigrationMode.sdkRead,
      'active' => SdkV2MigrationMode.sdkActive,
      _ => throw StateError('Unsupported SDK_V2_MODE: $rawMode'),
    };
    if (mode == SdkV2MigrationMode.sdkActive &&
        (!writerEnabled || !compatibilityApproved)) {
      throw StateError(
        'SDK active writer requires SDK_V2_WRITER_ENABLED=true and '
        'SDK_V2_COMPATIBILITY_APPROVED=true.',
      );
    }
    return SdkV2MigrationPolicy(
      mode: mode,
      writerGateEnabled: writerEnabled,
      compatibilityApproved: compatibilityApproved,
    );
  }

  final SdkV2MigrationMode mode;
  final bool writerGateEnabled;
  final bool compatibilityApproved;

  bool get usesSdkWriter =>
      mode == SdkV2MigrationMode.sdkActive &&
      writerGateEnabled &&
      compatibilityApproved;

  bool get usesSdkReader =>
      mode == SdkV2MigrationMode.sdkRead ||
      mode == SdkV2MigrationMode.sdkActive;

  bool get comparesShadow => mode == SdkV2MigrationMode.shadow;
}

enum SdkV2ResultCategory {
  success,
  historyUnavailable,
  recoveryPending,
  decryptError,
}

class SdkV2ShadowReport {
  const SdkV2ShadowReport({
    required this.conversationId,
    required this.isGroup,
    required this.matches,
    required this.legacyCategory,
    required this.sdkCategory,
  });

  final int conversationId;
  final bool isGroup;
  final bool matches;
  final SdkV2ResultCategory legacyCategory;
  final SdkV2ResultCategory sdkCategory;
}

typedef SdkV2ShadowReporter = void Function(SdkV2ShadowReport report);

class SdkV2HealthSnapshot {
  const SdkV2HealthSnapshot({
    required this.comparisons,
    required this.matches,
    required this.mismatches,
    required this.privateMismatches,
    required this.groupMismatches,
  });

  final int comparisons;
  final int matches;
  final int mismatches;
  final int privateMismatches;
  final int groupMismatches;

  bool get hasEvidence => comparisons > 0;
  bool get isCompatible => hasEvidence && mismatches == 0;
}

class SdkV2MigrationHealthMonitor {
  int _comparisons = 0;
  int _matches = 0;
  int _privateMismatches = 0;
  int _groupMismatches = 0;

  void record(SdkV2ShadowReport report) {
    _comparisons++;
    if (report.matches) {
      _matches++;
      return;
    }
    if (report.isGroup) {
      _groupMismatches++;
    } else {
      _privateMismatches++;
    }
  }

  SdkV2HealthSnapshot get snapshot => SdkV2HealthSnapshot(
    comparisons: _comparisons,
    matches: _matches,
    mismatches: _privateMismatches + _groupMismatches,
    privateMismatches: _privateMismatches,
    groupMismatches: _groupMismatches,
  );
}
