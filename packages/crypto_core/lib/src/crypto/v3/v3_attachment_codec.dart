import 'dart:convert';
import 'dart:math';

import 'v3_crypto_adapter.dart';

class V3EncryptedAttachment {
  const V3EncryptedAttachment({
    required this.filename,
    required this.mimeType,
    required this.sizeBytes,
    required this.ciphertext,
  });

  final String filename;
  final String mimeType;
  final int sizeBytes;
  final String ciphertext;

  Map<String, dynamic> toJson() => {
    'cipher_version': 'attachment:v3',
    'filename': filename,
    'mime_type': mimeType,
    'size_bytes': sizeBytes,
    'ciphertext': ciphertext,
  };
}

class V3AttachmentCodec {
  V3AttachmentCodec({required this.crypto});

  final V3CryptoAdapter crypto;
  static final _random = Random.secure();

  Future<V3EncryptedAttachment> encrypt({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required List<int> contentKey,
  }) async {
    final ad = utf8.encode('$filename|$mimeType|${bytes.length}');
    final encrypted = await crypto.encrypt(
      plaintext: bytes,
      associatedData: ad,
      context: {'content_key': contentKey, 'nonce': _nonce()},
    );
    return V3EncryptedAttachment(
      filename: filename,
      mimeType: mimeType,
      sizeBytes: bytes.length,
      ciphertext: base64Encode(encrypted),
    );
  }

  Future<List<int>> decrypt({
    required V3EncryptedAttachment attachment,
    required List<int> contentKey,
  }) {
    final ad = utf8.encode(
      '${attachment.filename}|${attachment.mimeType}|${attachment.sizeBytes}',
    );
    return crypto.decrypt(
      ciphertext: base64Decode(attachment.ciphertext),
      associatedData: ad,
      context: {'content_key': contentKey},
    );
  }

  List<int> _nonce() => List<int>.generate(12, (_) => _random.nextInt(256));
}
