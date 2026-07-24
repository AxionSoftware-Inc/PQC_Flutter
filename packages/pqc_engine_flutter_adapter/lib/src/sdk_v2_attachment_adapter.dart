import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:crypto_core/crypto_core.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

/// Bridges the SDK's byte-oriented attachment codec to Flutter's file API.
///
/// File selection, persistence, upload and retry remain host concerns. All
/// cryptographic material and wire-compatible chunk operations are delegated
/// to the standalone SDK.
class SdkV2AttachmentCryptoAdapter implements AttachmentCryptoProvider {
  SdkV2AttachmentCryptoAdapter({sdk.PqcV2Engine? engine})
    : _codec = (engine ?? sdk.PqcV2Engine()).attachment;

  final sdk.PqcV2AttachmentCodec _codec;

  @override
  AttachmentEncryptionDescriptor generateDescriptor() {
    return _fromSdkDescriptor(_codec.generateDescriptor());
  }

  @override
  Future<AttachmentEncryptionDescriptor> deriveEpochBoundDescriptor({
    required List<int> conversationEpochSecret,
    required String conversationEpochId,
    required String attachmentId,
    required int manifestSequence,
  }) async {
    final descriptor = await _codec.deriveEpochBoundDescriptor(
      conversationEpochSecret: conversationEpochSecret,
      conversationEpochId: conversationEpochId,
      attachmentId: attachmentId,
      manifestSequence: manifestSequence,
    );
    return _fromSdkDescriptor(descriptor);
  }

  @override
  Future<AttachmentFileAnalysis> analyzeFile({
    required File file,
    required int chunkSize,
  }) async {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    var plaintextSize = 0;
    await for (final chunk in file.openRead()) {
      plaintextSize += chunk.length;
    }
    final digest = await crypto.sha256.bind(file.openRead()).first;
    final totalChunks = plaintextSize == 0
        ? 0
        : (plaintextSize + chunkSize - 1) ~/ chunkSize;
    return AttachmentFileAnalysis(
      plaintextSize: plaintextSize,
      ciphertextSize: plaintextSize + (totalChunks * 16),
      totalChunks: totalChunks,
      plaintextSha256: digest.toString(),
    );
  }

  @override
  Future<String> buildManifestSha256(
    EncryptedAttachmentManifest manifest,
  ) async {
    return _codec.buildManifestSha256(
      sdk.PqcAttachmentManifest(
        filename: manifest.filename,
        mimeType: manifest.mimeType,
        cipherVersion: manifest.cipherVersion,
        chunkSize: manifest.chunkSize,
        plaintextSize: manifest.plaintextSize,
        ciphertextSize: manifest.ciphertextSize,
        totalChunks: manifest.totalChunks,
        plaintextSha256: manifest.plaintextSha256,
        fileKeyWrap: manifest.fileKeyWrap,
        conversationEpochId: manifest.conversationEpochId,
        recoveryManifestSequence: manifest.recoveryManifestSequence,
      ),
    );
  }

  @override
  Future<AttachmentChunkEncryptionResult> encryptChunk({
    required File file,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkSize,
    required int chunkIndex,
  }) async {
    if (chunkSize <= 0) {
      throw ArgumentError.value(chunkSize, 'chunkSize');
    }
    final handle = await file.open();
    try {
      await handle.setPosition(chunkSize * chunkIndex);
      final plaintext = await handle.read(chunkSize);
      final encrypted = await _codec.encryptChunk(
        plaintext: plaintext,
        descriptor: _toSdkDescriptor(descriptor),
        chunkIndex: chunkIndex,
      );
      return AttachmentChunkEncryptionResult(
        ciphertext: encrypted.ciphertext,
        plaintextLength: encrypted.plaintextLength,
      );
    } finally {
      await handle.close();
    }
  }

  @override
  Future<Uint8List> decryptChunk({
    required List<int> ciphertext,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkIndex,
  }) {
    return _codec.decryptChunk(
      ciphertext: ciphertext,
      descriptor: _toSdkDescriptor(descriptor),
      chunkIndex: chunkIndex,
    );
  }

  AttachmentEncryptionDescriptor _fromSdkDescriptor(
    sdk.PqcAttachmentDescriptor value,
  ) {
    return AttachmentEncryptionDescriptor(
      cipherVersion: value.cipherVersion,
      fileKeyBase64: value.fileKeyBase64,
      nonceSeedBase64: value.nonceSeedBase64,
      conversationEpochId: value.conversationEpochId,
      manifestSequence: value.manifestSequence,
    );
  }

  sdk.PqcAttachmentDescriptor _toSdkDescriptor(
    AttachmentEncryptionDescriptor value,
  ) {
    return sdk.PqcAttachmentDescriptor(
      cipherVersion: value.cipherVersion,
      fileKeyBase64: value.fileKeyBase64,
      nonceSeedBase64: value.nonceSeedBase64,
      conversationEpochId: value.conversationEpochId,
      manifestSequence: value.manifestSequence,
    );
  }
}
