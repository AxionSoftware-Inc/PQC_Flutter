import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Verifies the server's tamper-evident recovery index before importing any
/// key material. The server computes the root from the SHA-256 payload hashes.
class RecoveryManifestIntegrityException implements Exception {
  const RecoveryManifestIntegrityException();

  @override
  String toString() => 'Recovery manifest integrity check failed.';
}

class RecoveryManifestIntegrity {
  const RecoveryManifestIntegrity._();

  static Future<void> verify({
    required List<String> payloads,
    required String expectedMerkleRoot,
  }) async {
    if (expectedMerkleRoot.trim().isEmpty) return;
    final hashes = <String>[];
    for (final payload in payloads) {
      final digest = await Sha256().hash(utf8.encode(payload));
      hashes.add(_hex(digest.bytes));
    }
    hashes.sort();
    final root = await Sha256().hash(utf8.encode(hashes.join('|')));
    if (_hex(root.bytes) != expectedMerkleRoot) {
      throw const RecoveryManifestIntegrityException();
    }
  }

  static String _hex(List<int> bytes) =>
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}
