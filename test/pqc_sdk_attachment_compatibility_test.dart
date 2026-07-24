import 'dart:io';

import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_engine_flutter_adapter/pqc_engine_flutter_adapter.dart';

void main() {
  late Directory temporaryDirectory;
  late File input;
  late AttachmentCryptoService legacy;
  late SdkV2AttachmentCryptoAdapter sdk;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pqc-sdk-attachment-',
    );
    input = File('${temporaryDirectory.path}/fixture.bin');
    await input.writeAsBytes(List<int>.generate(513, (index) => index % 251));
    legacy = AttachmentCryptoService();
    sdk = SdkV2AttachmentCryptoAdapter();
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('SDK and frozen V2 derive identical epoch descriptors', () async {
    final secret = List<int>.generate(32, (index) => index + 1);
    final legacyDescriptor = await legacy.deriveEpochBoundDescriptor(
      conversationEpochSecret: secret,
      conversationEpochId: 'epoch-17',
      attachmentId: 'attachment-19',
      manifestSequence: 3,
    );
    final sdkDescriptor = await sdk.deriveEpochBoundDescriptor(
      conversationEpochSecret: secret,
      conversationEpochId: 'epoch-17',
      attachmentId: 'attachment-19',
      manifestSequence: 3,
    );

    expect(sdkDescriptor.toJson(), legacyDescriptor.toJson());
  });

  test(
    'SDK encrypted chunks are readable by frozen V2 and conversely',
    () async {
      final descriptor = await sdk.deriveEpochBoundDescriptor(
        conversationEpochSecret: List<int>.filled(32, 7),
        conversationEpochId: 'epoch-1',
        attachmentId: 'attachment-1',
        manifestSequence: 0,
      );

      final sdkEncrypted = await sdk.encryptChunk(
        file: input,
        descriptor: descriptor,
        chunkSize: 256,
        chunkIndex: 1,
      );
      final legacyClear = await legacy.decryptChunk(
        ciphertext: sdkEncrypted.ciphertext,
        descriptor: descriptor,
        chunkIndex: 1,
      );
      expect(legacyClear, await _readChunk(input, 256, 1));

      final legacyEncrypted = await legacy.encryptChunk(
        file: input,
        descriptor: descriptor,
        chunkSize: 256,
        chunkIndex: 2,
      );
      final sdkClear = await sdk.decryptChunk(
        ciphertext: legacyEncrypted.ciphertext,
        descriptor: descriptor,
        chunkIndex: 2,
      );
      expect(sdkClear, await _readChunk(input, 256, 2));
    },
  );

  test(
    'SDK and frozen V2 produce identical file analysis and manifest hash',
    () async {
      const chunkSize = 256;
      final legacyAnalysis = await legacy.analyzeFile(
        file: input,
        chunkSize: chunkSize,
      );
      final sdkAnalysis = await sdk.analyzeFile(
        file: input,
        chunkSize: chunkSize,
      );
      expect(sdkAnalysis.plaintextSize, legacyAnalysis.plaintextSize);
      expect(sdkAnalysis.ciphertextSize, legacyAnalysis.ciphertextSize);
      expect(sdkAnalysis.totalChunks, legacyAnalysis.totalChunks);
      expect(sdkAnalysis.plaintextSha256, legacyAnalysis.plaintextSha256);

      final manifest = EncryptedAttachmentManifest(
        filename: 'fixture.bin',
        mimeType: 'application/octet-stream',
        cipherVersion: AttachmentCryptoService.cipherVersion,
        chunkSize: chunkSize,
        plaintextSize: sdkAnalysis.plaintextSize,
        ciphertextSize: sdkAnalysis.ciphertextSize,
        totalChunks: sdkAnalysis.totalChunks,
        plaintextSha256: sdkAnalysis.plaintextSha256,
        manifestSha256: '',
        fileKeyWrap: 'wrapped-key',
        conversationEpochId: 'epoch-1',
        recoveryManifestSequence: 0,
      );

      expect(
        await sdk.buildManifestSha256(manifest),
        await legacy.buildManifestSha256(manifest),
      );
    },
  );
}

Future<List<int>> _readChunk(File file, int chunkSize, int chunkIndex) async {
  final handle = await file.open();
  try {
    await handle.setPosition(chunkSize * chunkIndex);
    return await handle.read(chunkSize);
  } finally {
    await handle.close();
  }
}
