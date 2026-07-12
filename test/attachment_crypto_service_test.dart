import 'dart:io';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attachment crypto service encrypts and decrypts chunks consistently', () async {
    final service = AttachmentCryptoService();
    final descriptor = service.generateDescriptor();
    final tempDir = await Directory.systemTemp.createTemp('attachment-crypto');
    final file = File('${tempDir.path}/sample.bin');
    final source = List<int>.generate(2048, (index) => index % 251);
    await file.writeAsBytes(source);

    final analysis = await service.analyzeFile(file: file, chunkSize: 512);
    expect(analysis.totalChunks, 4);

    final decrypted = <int>[];
    for (var chunkIndex = 0; chunkIndex < analysis.totalChunks; chunkIndex++) {
      final encrypted = await service.encryptChunk(
        file: file,
        descriptor: descriptor,
        chunkSize: 512,
        chunkIndex: chunkIndex,
      );
      final clear = await service.decryptChunk(
        ciphertext: encrypted.ciphertext,
        descriptor: descriptor,
        chunkIndex: chunkIndex,
      );
      decrypted.addAll(clear);
    }

    expect(decrypted, source);
    await tempDir.delete(recursive: true);
  });
}
