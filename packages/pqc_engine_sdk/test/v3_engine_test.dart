import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';
import 'package:test/test.dart';
import 'dart:convert';

void main() {
  test('standalone V3 attachment codec authenticates every chunk', () async {
    final engine = PqcV3Engine();
    final codec = PqcV3AttachmentCodec(engine.primitives);
    final descriptor = codec.generateDescriptor();
    final plaintext = List<int>.generate(257, (index) => index % 251);
    final encrypted = await codec.encryptChunk(
      plaintext: plaintext,
      descriptor: descriptor,
      chunkIndex: 3,
    );
    final decrypted = await codec.decryptChunk(
      ciphertext: encrypted.ciphertext,
      descriptor: descriptor,
      chunkIndex: 3,
    );

    expect(decrypted, orderedEquals(plaintext));
    expect(
      () => codec.decryptChunk(
        ciphertext: encrypted.ciphertext,
        descriptor: descriptor,
        chunkIndex: 4,
      ),
      throwsA(isA<Exception>()),
    );

    final manifest = PqcAttachmentManifest(
      filename: 'photo.bin',
      mimeType: 'application/octet-stream',
      cipherVersion: PqcV3WireAttachment.cipherVersion,
      chunkSize: 256,
      plaintextSize: plaintext.length,
      ciphertextSize: plaintext.length + 32,
      totalChunks: 2,
      plaintextSha256: List.filled(64, 'a').join(),
      fileKeyWrap: 'encrypted-key-envelope',
    );
    final manifestHash = codec.buildManifestSha256(manifest);
    expect(manifestHash, hasLength(64));
    expect(codec.verifyManifestSha256(manifest, manifestHash), isTrue);
    expect(codec.verifyManifestSha256(manifest, '${manifestHash}0'), isFalse);
  });

  test(
    'standalone V3 private engine round-trips with stable message id',
    () async {
      final engine = PqcV3Engine();
      final alice = engine.primitives.generateDeviceKeyset('alice-device');
      final bob = engine.primitives.generateDeviceKeyset('bob-device');
      const conversation = PqcConversation(id: 7, type: 'private');

      final payload = await engine.encodePrivate(
        conversation: conversation,
        plaintext: 'v3 message',
        sender: alice,
        recipientDevices: [bob.publicKey],
        messageId: 'client-message-7',
      );
      final decoded = await engine.decodePrivate(
        conversation: conversation,
        payload: payload,
        localKeysets: [bob],
        trustedSigningKeysByDevice: {
          alice.deviceId: {alice.signingPublicKeyBase64},
        },
      );

      expect(decoded, isA<PqcDecoded>());
      expect((decoded as PqcDecoded).plaintext, 'v3 message');
      expect(
        () => engine.encodePrivate(
          conversation: conversation,
          plaintext: 'missing id',
          sender: alice,
          recipientDevices: [bob.publicKey],
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'standalone V3 group engine binds the group epoch and recipients',
    () async {
      final engine = PqcV3Engine();
      final alice = engine.primitives.generateDeviceKeyset('alice-device');
      final bob = engine.primitives.generateDeviceKeyset('bob-device');
      const conversation = PqcConversation(id: 8, type: 'group');
      final payload = await engine.encodeGroup(
        conversation: conversation,
        plaintext: 'group v3 message',
        epoch: PqcGroupEpoch(
          epochId: 'epoch-1',
          secretKeyBytes: List.filled(32, 9),
        ),
        sender: alice,
        recipientDevices: [bob.publicKey],
        messageId: 'group-message-8',
      );

      final decoded = await engine.decodeGroup(
        conversation: conversation,
        payload: payload,
        epochsById: const {},
        localKeysets: [bob],
        trustedSigningKeysByDevice: {
          alice.deviceId: {alice.signingPublicKeyBase64},
        },
      );

      expect(decoded, isA<PqcDecoded>());
      expect((decoded as PqcDecoded).plaintext, 'group v3 message');
    },
  );

  test('V3 mutations never authenticate', () async {
    final engine = PqcV3Engine();
    final alice = engine.primitives.generateDeviceKeyset('alice-device');
    final bob = engine.primitives.generateDeviceKeyset('bob-device');
    const conversation = PqcConversation(id: 9, type: 'private');
    final payload = await engine.encodePrivate(
      conversation: conversation,
      plaintext: 'tamper target',
      sender: alice,
      recipientDevices: [bob.publicKey],
      messageId: 'tamper-message-9',
    );
    final index = payload.length - 3;
    final replacement = payload[index] == 'A' ? 'B' : 'A';
    final tampered = payload.replaceRange(index, index + 1, replacement);
    final decoded = await engine.decodePrivate(
      conversation: conversation,
      payload: tampered,
      localKeysets: [bob],
      trustedSigningKeysByDevice: {
        alice.deviceId: {alice.signingPublicKeyBase64},
      },
    );
    expect(decoded, isNot(isA<PqcDecoded>()));
  });

  test('V3 rejects a sender signing key bound to another KEM key', () async {
    final engine = PqcV3Engine();
    final alice = engine.primitives.generateDeviceKeyset('alice-device');
    final bob = engine.primitives.generateDeviceKeyset('bob-device');
    final attackerKem = engine.primitives.generateDeviceKeyset('attacker');
    const conversation = PqcConversation(id: 10, type: 'private');
    final payload = await engine.encodePrivate(
      conversation: conversation,
      plaintext: 'binding target',
      sender: alice,
      recipientDevices: [bob.publicKey],
      messageId: 'binding-message-10',
    );
    final encoded = payload.substring('${PqcV3Wire.privatePrefix}:'.length);
    final padded = encoded.padRight(
      encoded.length + ((4 - encoded.length % 4) % 4),
      '=',
    );
    final document = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(base64Url.decode(padded))) as Map,
    )..[PqcV3Wire.senderKemPublicKeyField] = attackerKem.kemPublicKeyBase64;
    final tampered =
        '${PqcV3Wire.privatePrefix}:${base64UrlEncode(utf8.encode(jsonEncode(document)))}';

    final decoded = await engine.decodePrivate(
      conversation: conversation,
      payload: tampered,
      localKeysets: [bob],
      trustedSigningKeysByDevice: {
        alice.deviceId: {alice.signingPublicKeyBase64},
      },
    );
    expect(decoded, isA<PqcDecodeError>());
    expect(
      (decoded as PqcDecodeError).failure,
      PqcDecodeFailure.corrupted,
    );
  });
}
