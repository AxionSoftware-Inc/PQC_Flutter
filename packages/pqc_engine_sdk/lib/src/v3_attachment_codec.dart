import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'primitives.dart';
import 'v2_attachment_codec.dart';

/// Pure byte-oriented PQCv3 attachment crypto.
///
/// The host owns files, streams, upload sessions and retry state. The SDK
/// owns the immutable descriptor, manifest and chunk wire contract.
class PqcV3AttachmentCodec {
  PqcV3AttachmentCodec(this._primitives);

  static const cipherVersion = PqcV3WireAttachment.cipherVersion;
  static const _domain = 'pqc-chat-attachment-v3';

  final PqcPrimitiveSuite _primitives;

  PqcAttachmentDescriptor generateDescriptor() => PqcAttachmentDescriptor(
    cipherVersion: cipherVersion,
    fileKeyBase64: base64Encode(_primitives.randomBytes(32)),
    nonceSeedBase64: base64Encode(_primitives.randomBytes(16)),
  );

  Future<PqcAttachmentDescriptor> deriveEpochBoundDescriptor({
    required List<int> conversationEpochSecret,
    required String conversationEpochId,
    required String attachmentId,
    required int manifestSequence,
  }) async {
    if (conversationEpochId.trim().isEmpty ||
        attachmentId.trim().isEmpty ||
        manifestSequence < 0 ||
        conversationEpochSecret.length != 32) {
      throw ArgumentError(
        'Epoch id and attachment id must be non-empty and the epoch secret '
        'must be exactly 32 bytes.',
      );
    }
    final material = await _primitives.deriveKey(
      secret: conversationEpochSecret,
      nonce: utf8.encode(conversationEpochId),
      info: utf8.encode('$_domain:$attachmentId:$manifestSequence'),
      length: 48,
    );
    return PqcAttachmentDescriptor(
      cipherVersion: cipherVersion,
      fileKeyBase64: base64Encode(material.sublist(0, 32)),
      nonceSeedBase64: base64Encode(material.sublist(32)),
      conversationEpochId: conversationEpochId,
      manifestSequence: manifestSequence,
    );
  }

  Future<PqcAttachmentChunk> encryptChunk({
    required List<int> plaintext,
    required PqcAttachmentDescriptor descriptor,
    required int chunkIndex,
  }) async {
    _validateDescriptor(descriptor);
    final box = await _primitives.encryptAead(
      plaintext: plaintext,
      key: base64Decode(descriptor.fileKeyBase64),
      nonce: _nonce(descriptor, chunkIndex),
      aad: _aad(descriptor, chunkIndex),
    );
    return PqcAttachmentChunk(
      ciphertext: [...box.ciphertext, ...box.mac],
      plaintextLength: plaintext.length,
    );
  }

  Future<Uint8List> decryptChunk({
    required List<int> ciphertext,
    required PqcAttachmentDescriptor descriptor,
    required int chunkIndex,
  }) async {
    _validateDescriptor(descriptor);
    if (ciphertext.length < 16) {
      throw StateError('Encrypted V3 attachment chunk is too short.');
    }
    final macStart = ciphertext.length - 16;
    return _primitives.decryptAead(
      box: PqcAeadBox(
        nonce: _nonce(descriptor, chunkIndex),
        ciphertext: ciphertext.sublist(0, macStart),
        mac: ciphertext.sublist(macStart),
      ),
      key: base64Decode(descriptor.fileKeyBase64),
      aad: _aad(descriptor, chunkIndex),
    );
  }

  String buildManifestSha256(PqcAttachmentManifest manifest) {
    validateManifest(manifest);
    final digest = crypto.sha256.convert(
      utf8.encode(jsonEncode(manifest.canonicalJson())),
    );
    return digest.toString();
  }

  bool verifyManifestSha256(
    PqcAttachmentManifest manifest,
    String expectedSha256,
  ) {
    final actual = buildManifestSha256(manifest);
    return _constantTimeEquals(
      utf8.encode(actual.toLowerCase()),
      utf8.encode(expectedSha256.toLowerCase()),
    );
  }

  void validateManifest(PqcAttachmentManifest manifest) {
    if (manifest.filename.trim().isEmpty ||
        manifest.mimeType.trim().isEmpty ||
        manifest.cipherVersion != cipherVersion ||
        manifest.chunkSize <= 0 ||
        manifest.plaintextSize < 0 ||
        manifest.ciphertextSize < 0 ||
        manifest.totalChunks < 0 ||
        manifest.recoveryManifestSequence < 0 ||
        manifest.fileKeyWrap.trim().isEmpty ||
        !_isSha256(manifest.plaintextSha256)) {
      throw const FormatException('Invalid V3 attachment manifest metadata.');
    }
    final expectedChunks = manifest.plaintextSize == 0
        ? 0
        : (manifest.plaintextSize + manifest.chunkSize - 1) ~/
              manifest.chunkSize;
    final expectedCiphertextSize =
        manifest.plaintextSize + (expectedChunks * 16);
    if (manifest.totalChunks != expectedChunks ||
        manifest.ciphertextSize != expectedCiphertextSize) {
      throw const FormatException(
        'V3 attachment manifest sizes are inconsistent.',
      );
    }
  }

  List<int> _aad(PqcAttachmentDescriptor descriptor, int chunkIndex) =>
      utf8.encode(
        jsonEncode({
          'domain': _domain,
          'cipher_version': descriptor.cipherVersion,
          'conversation_epoch_id': descriptor.conversationEpochId,
          'manifest_sequence': descriptor.manifestSequence,
          'chunk_index': chunkIndex,
        }),
      );

  Uint8List _nonce(PqcAttachmentDescriptor descriptor, int chunkIndex) {
    if (chunkIndex < 0) {
      throw ArgumentError.value(chunkIndex, 'chunkIndex');
    }
    final seed = base64Decode(descriptor.nonceSeedBase64);
    final index = ByteData(8)..setUint64(0, chunkIndex);
    return _primitives
        .sha256([
          ...utf8.encode('$_domain:nonce'),
          ...seed,
          ...index.buffer.asUint8List(),
        ])
        .sublist(0, 12);
  }

  bool _isSha256(String value) => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(value);

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

  void _validateDescriptor(PqcAttachmentDescriptor descriptor) {
    if (descriptor.cipherVersion != cipherVersion) {
      throw ArgumentError('V3 attachment descriptor has an invalid version.');
    }
    if (base64Decode(descriptor.fileKeyBase64).length != 32 ||
        base64Decode(descriptor.nonceSeedBase64).length != 16 ||
        descriptor.manifestSequence < 0) {
      throw ArgumentError('V3 attachment descriptor has invalid key material.');
    }
  }
}

abstract final class PqcV3WireAttachment {
  static const cipherVersion = 'attachment:v3';
}
