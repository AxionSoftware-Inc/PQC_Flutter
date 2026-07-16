import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'crypto_durability_models.dart';

/// Integrity boundary for locally persisted keysets. This is deliberately
/// separate from the wire codecs: a damaged local key must never be treated
/// as a valid historical key and produce confusing MAC errors.
class KeysetIntegrityException implements Exception {
  const KeysetIntegrityException(this.keysetId);

  final String keysetId;

  @override
  String toString() => 'Keyset integrity check failed: $keysetId';
}

class KeyStorageIntegrity {
  const KeyStorageIntegrity._();

  static Future<String> checksum(KeysetSnapshot snapshot) async {
    final digest = await Sha256().hash(
      utf8.encode(jsonEncode(_withoutIntegrity(snapshot))),
    );
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }

  static Future<KeysetSnapshot> seal(KeysetSnapshot snapshot) async {
    return snapshot.copyWith(integrityHash: await checksum(snapshot));
  }

  static Future<void> verify(KeysetSnapshot snapshot) async {
    final expected = snapshot.integrityHash;
    // Legacy keysets are upgraded on the next write. They remain readable so
    // a migration cannot strand existing history.
    if (expected == null || expected.isEmpty) return;
    if (expected != await checksum(snapshot)) {
      throw KeysetIntegrityException(snapshot.keysetId);
    }
  }

  static Map<String, dynamic> _withoutIntegrity(KeysetSnapshot snapshot) {
    final json = snapshot.toJson();
    json.remove('integrity_hash');
    return json;
  }
}
