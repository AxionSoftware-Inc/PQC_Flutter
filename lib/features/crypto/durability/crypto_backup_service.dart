import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../../core/storage/local_secret_store.dart';
import 'crypto_durability_models.dart';
import 'key_material_registry.dart';

class CryptoBackupService {
  CryptoBackupService({
    required this.keyMaterialRegistry,
    LocalSecretStore? secretStore,
    Pbkdf2? kdf,
    AesGcm? cipher,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _kdf =
           kdf ??
           Pbkdf2(
             macAlgorithm: Hmac.sha256(),
             iterations: 150000,
             bits: 256,
           ),
       _cipher = cipher ?? AesGcm.with256bits();

  static const _backupVersion = 1;
  static const _blobPrefix = 'crypto-backup:v1';

  final KeyMaterialRegistry keyMaterialRegistry;
  final LocalSecretStore _secretStore;
  final Pbkdf2 _kdf;
  final AesGcm _cipher;

  Future<String> exportEncryptedBackup(BackupExportRequest request) async {
    await keyMaterialRegistry.ensureCurrentKeysetRegistered();
    final keysets = await keyMaterialRegistry.readAllKeysets();
    final managedKeys = await _secretStore.listManagedKeys();
    final auxiliaryEntries = <String, String>{};
    for (final key in managedKeys) {
      if (!_shouldIncludeManagedKey(key)) {
        continue;
      }
      final value = await _secretStore.read(key);
      if (value == null || value.isEmpty) {
        continue;
      }
      auxiliaryEntries[key] = value;
    }
    final backupJson = jsonEncode({
      'version': _backupVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'keysets': keysets.map((item) => item.toJson()).toList(),
      'auxiliary_entries': auxiliaryEntries,
    });
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveSecretKey(
      passphrase: request.recoveryPassphrase,
      salt: salt,
    );
    final secretBox = await _cipher.encrypt(
      utf8.encode(backupJson),
      secretKey: secretKey,
      nonce: nonce,
    );
    return [
      _blobPrefix,
      base64Encode(salt),
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<void> importEncryptedBackup(BackupImportRequest request) async {
    if (!request.encryptedBlob.startsWith('$_blobPrefix:')) {
      throw ArgumentError('Unsupported backup blob format.');
    }
    final parts = request.encryptedBlob.substring(_blobPrefix.length + 1).split(':');
    if (parts.length != 4) {
      throw ArgumentError('Corrupted backup blob.');
    }
    final salt = base64Decode(parts[0]);
    final secretKey = await _deriveSecretKey(
      passphrase: request.recoveryPassphrase,
      salt: salt,
    );
    try {
      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[2]),
          nonce: base64Decode(parts[1]),
          mac: Mac(base64Decode(parts[3])),
        ),
        secretKey: secretKey,
      );
      final decoded = jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>;
      final version = decoded['version'] as int? ?? 0;
      if (version != _backupVersion) {
        throw ArgumentError('Unsupported backup version.');
      }
      final keysets = (decoded['keysets'] as List<dynamic>? ?? const [])
          .map((item) => KeysetSnapshot.fromJson(item as Map<String, dynamic>))
          .toList();
      final auxiliaryEntries =
          (decoded['auxiliary_entries'] as Map<String, dynamic>? ?? const {})
              .map((key, value) => MapEntry(key, value as String));
      await keyMaterialRegistry.importKeysets(keysets);
      for (final entry in auxiliaryEntries.entries) {
        await _secretStore.write(key: entry.key, value: entry.value);
      }
    } on SecretBoxAuthenticationError {
      throw ArgumentError('Recovery passphrase is invalid.');
    }
  }

  bool _shouldIncludeManagedKey(String key) {
    return key == 'device_profile_snapshot_v2' ||
        key.startsWith('group_secret_key_') ||
        key.startsWith('group_participant_signature_');
  }

  Future<SecretKey> _deriveSecretKey({
    required String passphrase,
    required List<int> salt,
  }) {
    return _kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}
