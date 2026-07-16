import 'dart:convert';

import 'package:crypto_core/crypto_core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keyset checksum rejects a corrupted secret without deleting it',
    () async {
      final original = _snapshot();
      final sealed = await KeyStorageIntegrity.seal(original);
      final tampered = KeysetSnapshot.fromJson({
        ...sealed.toJson(),
        'pqc_secret_key': base64Encode(List<int>.filled(32, 7)),
      });

      expect(
        () => KeyStorageIntegrity.verify(tampered),
        throwsA(isA<KeysetIntegrityException>()),
      );
      expect(tampered.keysetId, sealed.keysetId);
    },
  );

  test('recovery merkle root rejects missing or reordered records', () async {
    const payloads = ['keyset-a', 'keyset-b'];
    final hashes = <String>[];
    for (final payload in payloads) {
      hashes.add(await _sha256Hex(payload));
    }
    hashes.sort();
    final root = await _sha256Hex(hashes.join('|'));

    await RecoveryManifestIntegrity.verify(
      payloads: payloads.reversed.toList(),
      expectedMerkleRoot: root,
    );
    expect(
      () => RecoveryManifestIntegrity.verify(
        payloads: const ['keyset-a'],
        expectedMerkleRoot: root,
      ),
      throwsA(isA<RecoveryManifestIntegrityException>()),
    );
  });
}

Future<String> _sha256Hex(String value) async {
  final digest = await Sha256().hash(utf8.encode(value));
  return digest.bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

KeysetSnapshot _snapshot() {
  return KeysetSnapshot(
    keysetId: 'chaos-keyset',
    deviceId: 'chaos-device',
    identityAlgorithm: 'x25519',
    identityPublicKey: 'public',
    identityPrivateKey: 'private',
    pqcAlgorithm: 'ml-kem-768',
    pqcPublicKey: 'pqc-public',
    pqcSecretKey: 'pqc-secret',
    pqcSigningAlgorithm: 'ml-dsa-65',
    pqcSigningPublicKey: 'sign-public',
    pqcSigningSecretKey: 'sign-secret',
    status: 'active',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
