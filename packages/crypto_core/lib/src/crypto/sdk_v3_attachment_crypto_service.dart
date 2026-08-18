import 'dart:io';
import 'dart:typed_data';

import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

import '../models/attachment_transfer.dart';
import 'attachment_crypto_service.dart';

/// Flutter file/stream adapter for the standalone PQCv3 attachment codec.
class SdkV3AttachmentCryptoService extends AttachmentCryptoService {
  SdkV3AttachmentCryptoService({sdk.PqcV3Engine? engine})
    : _codec = (engine ?? sdk.PqcV3Engine()).attachment,
      super();

  final sdk.PqcV3AttachmentCodec _codec;

  @override
  AttachmentEncryptionDescriptor generateDescriptor() =>
      _toHostDescriptor(_codec.generateDescriptor());

  @override
  Future<AttachmentEncryptionDescriptor> deriveEpochBoundDescriptor({
    required List<int> conversationEpochSecret,
    required String conversationEpochId,
    required String attachmentId,
    required int manifestSequence,
  }) async => _toHostDescriptor(
    await _codec.deriveEpochBoundDescriptor(
      conversationEpochSecret: conversationEpochSecret,
      conversationEpochId: conversationEpochId,
      attachmentId: attachmentId,
      manifestSequence: manifestSequence,
    ),
  );

  @override
  Future<String> buildManifestSha256(
    EncryptedAttachmentManifest manifest,
  ) async => _codec.buildManifestSha256(
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

  @override
  Future<AttachmentChunkEncryptionResult> encryptChunk({
    required File file,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkSize,
    required int chunkIndex,
  }) async {
    final raf = await file.open();
    try {
      await raf.setPosition(chunkSize * chunkIndex);
      final encrypted = await _codec.encryptChunk(
        plaintext: await raf.read(chunkSize),
        descriptor: _toSdkDescriptor(descriptor),
        chunkIndex: chunkIndex,
      );
      return AttachmentChunkEncryptionResult(
        ciphertext: Uint8List.fromList(encrypted.ciphertext),
        plaintextLength: encrypted.plaintextLength,
      );
    } finally {
      await raf.close();
    }
  }

  @override
  Future<Uint8List> decryptChunk({
    required List<int> ciphertext,
    required AttachmentEncryptionDescriptor descriptor,
    required int chunkIndex,
  }) => _codec.decryptChunk(
    ciphertext: ciphertext,
    descriptor: _toSdkDescriptor(descriptor),
    chunkIndex: chunkIndex,
  );

  sdk.PqcAttachmentDescriptor _toSdkDescriptor(
    AttachmentEncryptionDescriptor descriptor,
  ) => sdk.PqcAttachmentDescriptor(
    cipherVersion: descriptor.cipherVersion,
    fileKeyBase64: descriptor.fileKeyBase64,
    nonceSeedBase64: descriptor.nonceSeedBase64,
    conversationEpochId: descriptor.conversationEpochId,
    manifestSequence: descriptor.manifestSequence,
  );

  AttachmentEncryptionDescriptor _toHostDescriptor(
    sdk.PqcAttachmentDescriptor descriptor,
  ) => AttachmentEncryptionDescriptor(
    cipherVersion: descriptor.cipherVersion,
    fileKeyBase64: descriptor.fileKeyBase64,
    nonceSeedBase64: descriptor.nonceSeedBase64,
    conversationEpochId: descriptor.conversationEpochId,
    manifestSequence: descriptor.manifestSequence,
  );
}
