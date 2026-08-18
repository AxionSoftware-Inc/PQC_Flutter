import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

abstract final class PqcV2Wire {
  static const protocolVersion = 2;
  static const privatePrefix = 'pqc:v2';
  static const groupPrefix = 'group:v2';
  static const groupWrapPrefix = 'group-wrap:pqc:v2';
  static const groupWrapV25Prefix = 'group-wrap:pqc:v2.5';
  static const privateAlgorithm = 'ml-kem-768+a256gcm+ml-dsa-65';
  static const groupAlgorithm = 'a256gcm+group-ml-kem-768';
  static const groupEnvelopeAlgorithm = 'group-ml-kem-768-aesgcm-v2';
  static const groupEnvelopeV25Algorithm = 'group-ml-kem-768-aesgcm-v2.5';
  static const attachmentCipherVersion = 'attachment:v2';
}

class PqcConversation {
  const PqcConversation({required this.id, required this.type});

  final int id;
  final String type;

  bool get isGroup => type == 'group';
}

class PqcDevicePublicKey {
  const PqcDevicePublicKey({
    required this.deviceId,
    required this.kemPublicKeyBase64,
    required this.signingPublicKeyBase64,
  });

  final String deviceId;
  final String kemPublicKeyBase64;
  final String signingPublicKeyBase64;

  String get keysetId => computeKeysetId(deviceId, kemPublicKeyBase64);

  /// Identity that binds both public keys for new protocol engines.
  ///
  /// [keysetId] is intentionally retained as the frozen V2 identifier. A V2
  /// payload must never silently change its keyset-id calculation.
  String get bindingId => computeKeysetBindingId(
    deviceId,
    kemPublicKeyBase64,
    signingPublicKeyBase64,
  );
}

class PqcDeviceKeyset {
  const PqcDeviceKeyset({
    required this.deviceId,
    required this.kemPublicKeyBase64,
    required this.kemSecretKeyBase64,
    required this.signingPublicKeyBase64,
    required this.signingSecretKeyBase64,
  });

  final String deviceId;
  final String kemPublicKeyBase64;
  final String kemSecretKeyBase64;
  final String signingPublicKeyBase64;
  final String signingSecretKeyBase64;

  String get keysetId => computeKeysetId(deviceId, kemPublicKeyBase64);

  /// Identity that binds both public keys for new protocol engines.
  String get bindingId => computeKeysetBindingId(
    deviceId,
    kemPublicKeyBase64,
    signingPublicKeyBase64,
  );

  PqcDevicePublicKey get publicKey => PqcDevicePublicKey(
    deviceId: deviceId,
    kemPublicKeyBase64: kemPublicKeyBase64,
    signingPublicKeyBase64: signingPublicKeyBase64,
  );
}

class PqcGroupEpoch {
  PqcGroupEpoch({required this.epochId, required List<int> secretKeyBytes})
    : secretKeyBytes = List<int>.unmodifiable(secretKeyBytes);

  final String epochId;
  final List<int> secretKeyBytes;
}

enum PqcDecodeFailure {
  unsupported,
  bindingMismatch,
  untrustedSender,
  keyMissing,
  corrupted,
}

sealed class PqcDecodeResult {
  const PqcDecodeResult();

  bool get isSuccess => this is PqcDecoded;
}

class PqcDecoded extends PqcDecodeResult {
  const PqcDecoded({required this.plaintext, required this.protocolVersion});

  final String plaintext;
  final int protocolVersion;
}

class PqcDecodeError extends PqcDecodeResult {
  const PqcDecodeError(this.failure, {this.details = ''});

  final PqcDecodeFailure failure;
  final String details;
}

class PqcRemoteCapabilities {
  PqcRemoteCapabilities({
    required Set<String> privateReadPrefixes,
    required Set<String> groupReadPrefixes,
    required Set<String> privateWritePrefixes,
    required Set<String> groupWritePrefixes,
    required Set<String> attachmentCipherVersions,
    required this.minimumDecoderVersion,
    Set<String> groupEnvelopeReadPrefixes = const {},
    Set<String> groupEnvelopeWritePrefixes = const {},
  }) : privateReadPrefixes = Set.unmodifiable(privateReadPrefixes),
       groupReadPrefixes = Set.unmodifiable(groupReadPrefixes),
       privateWritePrefixes = Set.unmodifiable(privateWritePrefixes),
       groupWritePrefixes = Set.unmodifiable(groupWritePrefixes),
       attachmentCipherVersions = Set.unmodifiable(attachmentCipherVersions),
       groupEnvelopeReadPrefixes = Set.unmodifiable(groupEnvelopeReadPrefixes),
       groupEnvelopeWritePrefixes = Set.unmodifiable(
         groupEnvelopeWritePrefixes,
       );

  /// Parses both the SDK shape and the backend capability endpoint shape.
  /// Backend releases historically returned `minimum_decoder_version` as a
  /// string, so the boundary normalizes it once instead of leaking that
  /// mismatch into every writer gate.
  factory PqcRemoteCapabilities.fromJson(Map<String, dynamic> json) {
    String normalizePrefix(String value) =>
        value.endsWith(':') ? value.substring(0, value.length - 1) : value;

    Set<String> readSet(String key, String legacyKey) => {
      ...(json[key] as List<dynamic>? ?? const []).whereType<String>().map(
        normalizePrefix,
      ),
      ...(json[legacyKey] as List<dynamic>? ?? const [])
          .whereType<String>()
          .map(normalizePrefix),
    };

    final minimum = json['minimum_decoder_version'];
    final minimumVersion = minimum is int
        ? minimum
        : int.tryParse(minimum?.toString().split('.').first ?? '') ?? 0;
    return PqcRemoteCapabilities(
      privateReadPrefixes: readSet(
        'readable_private_message_prefixes',
        'private_read_prefixes',
      ),
      groupReadPrefixes: readSet(
        'readable_group_message_prefixes',
        'group_read_prefixes',
      ),
      privateWritePrefixes: readSet(
        'private_message_prefixes',
        'private_write_prefixes',
      ),
      groupWritePrefixes: readSet(
        'group_message_prefixes',
        'group_write_prefixes',
      ),
      attachmentCipherVersions: {
        ...(json['attachment_cipher_versions'] as List<dynamic>? ?? const [])
            .whereType<String>(),
      },
      minimumDecoderVersion: minimumVersion,
      groupEnvelopeReadPrefixes: readSet(
        'readable_group_envelope_prefixes',
        'group_envelope_read_prefixes',
      ),
      groupEnvelopeWritePrefixes: readSet(
        'group_envelope_prefixes',
        'group_envelope_write_prefixes',
      ),
    );
  }

  final Set<String> privateReadPrefixes;
  final Set<String> groupReadPrefixes;
  final Set<String> privateWritePrefixes;
  final Set<String> groupWritePrefixes;
  final Set<String> attachmentCipherVersions;
  final Set<String> groupEnvelopeReadPrefixes;
  final Set<String> groupEnvelopeWritePrefixes;
  final int minimumDecoderVersion;
}

String computeKeysetId(String deviceId, String kemPublicKeyBase64) {
  final digest = crypto.sha256.convert(
    utf8.encode('$deviceId|$kemPublicKeyBase64'),
  );
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

String computeKeysetBindingId(
  String deviceId,
  String kemPublicKeyBase64,
  String signingPublicKeyBase64,
) {
  final canonical = jsonEncode({
    'device_id': deviceId,
    'kem_public_key': kemPublicKeyBase64,
    'signing_public_key': signingPublicKeyBase64,
  });
  final digest = crypto.sha256.convert(utf8.encode(canonical));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}
