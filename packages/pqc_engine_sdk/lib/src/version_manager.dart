import 'models.dart';
import 'primitives.dart';
import 'v2_engine.dart';
import 'v3_engine.dart';

enum PqcConversationKind { private, group, groupEnvelope }

class PqcCompatibilityException implements Exception {
  const PqcCompatibilityException(this.message);

  final String message;

  @override
  String toString() => 'PqcCompatibilityException: $message';
}

/// Registry and production write gate for independently versioned engines.
///
/// A recognized payload is offered to exactly one decoder. A cryptographic
/// failure is never retried as another protocol, preventing downgrade bugs.
class PqcEngineManager {
  PqcEngineManager({
    required Iterable<PqcEngine> decoders,
    String? activeWriterId,
    Map<PqcConversationKind, String>? activeWriterIds,
    bool writerEnabled = false,
  }) : this._(
         decoders: _registerDecoders(decoders),
         activeWriterId: activeWriterId,
         activeWriterIds: activeWriterIds,
         writerEnabled: writerEnabled,
       );

  PqcEngineManager._({
    required Map<String, PqcEngine> decoders,
    required String? activeWriterId,
    required Map<PqcConversationKind, String>? activeWriterIds,
    required this.writerEnabled,
  }) : _decoders = decoders,
       _activeWriterIds = _resolveWriterIds(
         decoders: decoders,
         activeWriterId: activeWriterId,
         activeWriterIds: activeWriterIds,
       );

  /// Builds the production writer map for one of the shared release profiles.
  ///
  /// V3 intentionally uses the frozen V2 engine for group-key envelopes while
  /// private and group messages use V3. This mixed mapping is part of the
  /// compatibility contract and cannot be represented by one global writer
  /// id.
  factory PqcEngineManager.forRelease({
    required PqcProtocolRelease release,
    PqcPrimitiveSuite? primitives,
    bool writerEnabled = false,
  }) {
    switch (release.profileId) {
      case 'v2':
        final v2 = PqcV2Engine(primitives: primitives);
        return PqcEngineManager(
          decoders: [v2],
          activeWriterIds: {
            for (final kind in PqcConversationKind.values) kind: v2.engineId,
          },
          writerEnabled: writerEnabled,
        );
      case 'v2.5':
        final v25 = PqcV2Engine(
          primitives: primitives,
          enableV25GroupEnvelopeWriter: true,
        );
        return PqcEngineManager(
          decoders: [v25],
          activeWriterIds: {
            for (final kind in PqcConversationKind.values) kind: v25.engineId,
          },
          writerEnabled: writerEnabled,
        );
      case 'v3':
        final v2 = PqcV2Engine(primitives: primitives);
        final v3 = PqcV3Engine(primitives: primitives);
        return PqcEngineManager(
          decoders: [v2, v3],
          activeWriterIds: {
            PqcConversationKind.private: v3.engineId,
            PqcConversationKind.group: v3.engineId,
            PqcConversationKind.groupEnvelope: v2.engineId,
          },
          writerEnabled: writerEnabled,
        );
      default:
        throw ArgumentError.value(
          release.profileId,
          'release',
          'Unsupported protocol release profile.',
        );
    }
  }

  final Map<String, PqcEngine> _decoders;
  final Map<PqcConversationKind, String> _activeWriterIds;
  final bool writerEnabled;

  static Map<PqcConversationKind, String> _resolveWriterIds({
    required Map<String, PqcEngine> decoders,
    required String? activeWriterId,
    required Map<PqcConversationKind, String>? activeWriterIds,
  }) {
    if (decoders.isEmpty) {
      throw ArgumentError('At least one decoder must be registered.');
    }
    if (activeWriterId != null && activeWriterIds != null) {
      throw ArgumentError(
        'Provide activeWriterId or activeWriterIds, not both.',
      );
    }
    final selected = <PqcConversationKind, String>{};
    if (activeWriterId != null) {
      for (final kind in PqcConversationKind.values) {
        selected[kind] = activeWriterId;
      }
    } else if (activeWriterIds != null) {
      selected.addAll(activeWriterIds);
    }
    for (final entry in selected.entries) {
      if (entry.value.trim().isEmpty || !decoders.containsKey(entry.value)) {
        throw ArgumentError(
          'Active writer for ${entry.key} must be a registered engine.',
        );
      }
    }
    return Map.unmodifiable(selected);
  }

  static Map<String, PqcEngine> _registerDecoders(Iterable<PqcEngine> source) {
    final engines = List<PqcEngine>.of(source, growable: false);
    final registered = <String, PqcEngine>{};
    final privatePrefixes = <String>{};
    final groupPrefixes = <String>{};
    final groupEnvelopePrefixes = <String>{};
    for (final engine in engines) {
      if (engine.engineId.trim().isEmpty) {
        throw ArgumentError('Engine ids must not be empty.');
      }
      if (engine.protocolVersion <= 0 ||
          engine.privatePrefix.trim().isEmpty ||
          engine.groupPrefix.trim().isEmpty) {
        throw ArgumentError('Engine metadata must be stable and non-empty.');
      }
      if (registered.containsKey(engine.engineId)) {
        throw ArgumentError('Engine ids must be unique.');
      }
      if (engine.attachmentCipherVersions.any((item) => item.trim().isEmpty) ||
          engine.groupEnvelopeReadPrefixes.any((item) => item.trim().isEmpty) ||
          engine.groupEnvelopeWritePrefixes.any(
            (item) => item.trim().isEmpty,
          ) ||
          !privatePrefixes.add(engine.privatePrefix) ||
          !groupPrefixes.add(engine.groupPrefix) ||
          !engine.groupEnvelopeReadPrefixes.every(groupEnvelopePrefixes.add)) {
        throw ArgumentError('Engine payload prefixes must be unique.');
      }
      registered[engine.engineId] = engine;
    }
    return registered;
  }

  List<PqcEngine> get decoders => List.unmodifiable(_decoders.values);

  String? get activeWriterId => _activeWriterIds[PqcConversationKind.private];

  PqcEngine? get activeWriter => activeWriterFor(PqcConversationKind.private);

  PqcEngine? activeWriterFor(PqcConversationKind kind) {
    final id = _activeWriterIds[kind];
    return id == null ? null : _decoders[id];
  }

  Map<PqcConversationKind, PqcEngine> get activeWriters => {
    for (final entry in _activeWriterIds.entries)
      entry.key: _decoders[entry.value]!,
  };

  PqcEngine resolveDecoder({
    required PqcConversationKind kind,
    required String payload,
  }) {
    final matches = _decoders.values
        .where((engine) {
          return switch (kind) {
            PqcConversationKind.private => engine.recognizesPrivate(payload),
            PqcConversationKind.group => engine.recognizesGroup(payload),
            PqcConversationKind.groupEnvelope => engine.recognizesGroupEnvelope(
              payload,
            ),
          };
        })
        .toList(growable: false);
    if (matches.isEmpty) {
      throw const PqcCompatibilityException('Unsupported payload format.');
    }
    if (matches.length != 1) {
      throw const PqcCompatibilityException(
        'Ambiguous payload format registration.',
      );
    }
    return matches.single;
  }

  PqcEngine requireWriter({
    required PqcConversationKind kind,
    required PqcRemoteCapabilities remote,
    bool hasAttachments = false,
  }) {
    final writer = activeWriterFor(kind);
    if (!writerEnabled || writer == null) {
      throw const PqcCompatibilityException(
        'Encrypted writer is disabled by the production gate.',
      );
    }
    if (kind == PqcConversationKind.groupEnvelope &&
        (writer is! PqcGroupEnvelopeEngine ||
            writer.groupEnvelopeWritePrefixes.isEmpty)) {
      throw PqcCompatibilityException(
        'The selected engine cannot encode group-key envelopes.',
      );
    }
    final readable = switch (kind) {
      PqcConversationKind.private => remote.privateReadPrefixes.contains(
        writer.privatePrefix,
      ),
      PqcConversationKind.group => remote.groupReadPrefixes.contains(
        writer.groupPrefix,
      ),
      PqcConversationKind.groupEnvelope =>
        writer.groupEnvelopeWritePrefixes.every(
          remote.groupEnvelopeReadPrefixes.contains,
        ),
    };
    final writable = switch (kind) {
      PqcConversationKind.private => remote.privateWritePrefixes.contains(
        writer.privatePrefix,
      ),
      PqcConversationKind.group => remote.groupWritePrefixes.contains(
        writer.groupPrefix,
      ),
      PqcConversationKind.groupEnvelope =>
        writer.groupEnvelopeWritePrefixes.every(
          remote.groupEnvelopeWritePrefixes.contains,
        ),
    };
    if (!readable || !writable) {
      throw PqcCompatibilityException(
        'Remote endpoint cannot safely read and write ${writer.engineId}.',
      );
    }
    if (remote.minimumDecoderVersion <= 0) {
      throw const PqcCompatibilityException(
        'Remote endpoint did not provide a valid decoder version.',
      );
    }
    if (writer.protocolVersion < remote.minimumDecoderVersion) {
      throw PqcCompatibilityException(
        'Remote endpoint requires decoder version '
        '${remote.minimumDecoderVersion} or newer.',
      );
    }
    if (hasAttachments &&
        !writer.attachmentCipherVersions.every(
          remote.attachmentCipherVersions.contains,
        )) {
      throw const PqcCompatibilityException(
        'Attachment cipher capability mismatch.',
      );
    }
    return writer;
  }
}
