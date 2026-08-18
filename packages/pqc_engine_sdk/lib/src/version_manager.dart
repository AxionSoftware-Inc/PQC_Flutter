import 'models.dart';
import 'v2_engine.dart';

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
    this.writerEnabled = false,
  }) : _decoders = _registerDecoders(decoders),
       _activeWriterId = activeWriterId {
    if (_decoders.isEmpty) {
      throw ArgumentError('At least one decoder must be registered.');
    }
    if (activeWriterId != null && !_decoders.containsKey(activeWriterId)) {
      throw ArgumentError('Active writer must be a registered engine.');
    }
  }

  final Map<String, PqcEngine> _decoders;
  final String? _activeWriterId;
  final bool writerEnabled;

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
      if (!privatePrefixes.add(engine.privatePrefix) ||
          !groupPrefixes.add(engine.groupPrefix) ||
          !engine.groupEnvelopeReadPrefixes.every(groupEnvelopePrefixes.add)) {
        throw ArgumentError('Engine payload prefixes must be unique.');
      }
      registered[engine.engineId] = engine;
    }
    return registered;
  }

  List<PqcEngine> get decoders => List.unmodifiable(_decoders.values);

  PqcEngine? get activeWriter =>
      _activeWriterId == null ? null : _decoders[_activeWriterId];

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
    final writer = activeWriter;
    if (!writerEnabled || writer == null) {
      throw const PqcCompatibilityException(
        'Encrypted writer is disabled by the production gate.',
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
