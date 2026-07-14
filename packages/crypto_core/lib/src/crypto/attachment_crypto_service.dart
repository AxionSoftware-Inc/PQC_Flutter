import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../models/attachment_transfer.dart';
import 'durability/v2_protocol_contract.dart';

class AttachmentChunkEncryptionResult {
  const AttachmentChunkEncryptionResult({
    required this.ciphertext,
    required this.plaintextLength,
  });

  final Uint8List ciphertext;
  final int plaintextLength;
}

class AttachmentFileAnalysis {
  const AttachmentFileAnalysis({
    required this.plaintextSize,
    required this.ciphertextSize,
    required this.totalChunks,
    required this.plaintextSha256,
  });

  final int plaintextSize;
  final int ciphertextSize;
  final int totalChunks;
  final String plaintextSha256;
}

class AttachmentCryptoService {
  AttachmentCryptoService({Cipher? cipher, Random? random})
    : _cipher = cipher ?? AesGcm.with256bits(),
      _random = random ?? Random.secure();

  static const cipherVersion = PqcV2ProtocolContract.attachmentCipherVersion;

  final Cipher _cipher;
  final Random _random;

  AttachmentEncryptionDescriptor generateDescriptor() {
    final key = Uint8List.fromList(
      List<int>.generate(32, (_) => _random.nextInt(256)),
    );
    final nonceSeed = Uint8List.fromList(
      List<int>.generate(16, (_) => _random.nextInt(256)),
    );
    return AttachmentEncryptionDescriptor(
      cipherVersion: cipherVersion,
      fileKeyBase64: base64Encode(key),
      nonceSeedBase64: base64Encode(nonceSeed),
    );
  }

  /// Deterministic attachment material bound to an immutable PQCv2 epoch.
  /// Callers must provide a recovered conversation epoch secret, never a
  /// device-local random key, when durable enterprise history is required.
  Future<AttachmentEncryptionDescriptor> deriveEpochBoundDescriptor({
    required List<int> conversationEpochSecret,
    required String conversationEpochId,
    required String attachmentId,
    required int manifestSequence,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 48);
    final derivedKey = await hkdf.deriveKey(
      secretKey: SecretKey(conversationEpochSecret),
      nonce: utf8.encode(conversationEpochId),
      info: utf8.encode(
        'pqc-chat-attachment-v2:$attachmentId:$manifestSequence',
      ),
    );
    final material = await derivedKey.extractBytes();
    return AttachmentEncryptionDescriptor(
      cipherVersion: cipherVersion,
      fileKeyBase64: base64Encode(material.sublist(0, 32)),
      nonceSeedBase64: base64Encode(material.sublist(32)),
      conversationEpochId: conversationEpochId,
      manifestSequence: manifestSequence,
    );
  }

  Future<AttachmentFileAnalysis> analyzeFile({
    required File file,
    required int chunkSize,
  }) async {
    var plaintextSize = 0;
    await for (final chunk in file.openRead()) {
      plaintextSize += chunk.length;
    }
    final digest = await crypto.sha256.bind(file.openRead()).first;
    final plaintextSha256 = digest.toString();
    final totalChunks = ((plaintextSize + chunkSize - 1) / chunkSize).floor();
    final ciphertextSize = plaintextSize + (totalChunks * 16);
    return AttachmentFileAnalysis(
      plaintextSize: plaintextSize,
      ciphertextSize: ciphertextSize,
      totalChunks: totalChunks,
      plaintextSha256: plaintextSha256,
    );
  }

  Future<String> buildManifestSha256(
    EncryptedAttachmentManifest manifest,
  ) async {
    final canonical = jsonEncode({
      'filename': manifest.filename,
      'mime_type': manifest.mimeType,
      'cipher_version': manifest.cipherVersion,
      'chunk_size': manifest.chunkSize,
      'plaintext_size': manifest.plaintextSize,
      'ciphertext_size': manifest.ciphertextSize,
      'total_chunks': manifest.totalChunks,
      'plaintext_sha256': manifest.plaintextSha256,
      'file_key_wrap': manifest.fileKeyWrap,
      'conversation_epoch_id': manifest.conversationEpochId,
      'recovery_manifest_sequence': manifest.recoveryManifestSequence,
    });
    return crypto.sha256.convert(utf8.encode(canonical)).toString();
  }

  Future<AttachmentChunkEncryptionResult> encryptChunk({
    required File file,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkSize,
    required int chunkIndex,
  }) async {
    final raf = await file.open();
    try {
      final offset = chunkSize * chunkIndex;
      await raf.setPosition(offset);
      final plaintext = await raf.read(chunkSize);
      final secretKey = SecretKey(base64Decode(descriptor.fileKeyBase64));
      final nonce = await _deriveNonce(
        descriptor: descriptor,
        chunkIndex: chunkIndex,
      );
      final secretBox = await _cipher.encrypt(
        plaintext,
        secretKey: secretKey,
        nonce: nonce,
      );
      final ciphertext = Uint8List.fromList([
        ...secretBox.cipherText,
        ...secretBox.mac.bytes,
      ]);
      return AttachmentChunkEncryptionResult(
        ciphertext: ciphertext,
        plaintextLength: plaintext.length,
      );
    } finally {
      await raf.close();
    }
  }

  Future<Uint8List> decryptChunk({
    required List<int> ciphertext,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkIndex,
  }) async {
    if (ciphertext.length < 16) {
      throw StateError('Encrypted attachment chunk is too short.');
    }
    final secretKey = SecretKey(base64Decode(descriptor.fileKeyBase64));
    final nonce = await _deriveNonce(
      descriptor: descriptor,
      chunkIndex: chunkIndex,
    );
    final macStart = ciphertext.length - 16;
    final secretBox = SecretBox(
      ciphertext.sublist(0, macStart),
      nonce: nonce,
      mac: Mac(ciphertext.sublist(macStart)),
    );
    final clear = await _cipher.decrypt(secretBox, secretKey: secretKey);
    return Uint8List.fromList(clear);
  }

  Future<List<int>> _deriveNonce({
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkIndex,
  }) async {
    final seed = base64Decode(descriptor.nonceSeedBase64);
    final chunkIndexBytes = ByteData(8)..setUint64(0, chunkIndex);
    final input = Uint8List.fromList([
      ...seed,
      ...chunkIndexBytes.buffer.asUint8List(),
    ]);
    return crypto.sha256.convert(input).bytes.sublist(0, 12);
  }
}
