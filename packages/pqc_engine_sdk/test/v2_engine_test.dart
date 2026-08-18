import 'dart:convert';

import 'package:pqc_engine_sdk/pqc_engine_sdk.dart';
import 'package:test/test.dart';

void main() {
  final primitives = DartPqcPrimitiveSuite();
  late PqcV2Engine engine;
  late PqcDeviceKeyset alice;
  late PqcDeviceKeyset bob;
  late PqcDeviceKeyset bobRotated;
  late PqcDeviceKeyset carol;

  setUpAll(() {
    engine = PqcV2Engine(primitives: primitives);
    alice = primitives.generateDeviceKeyset('alice-phone');
    bob = primitives.generateDeviceKeyset('bob-tablet');
    bobRotated = primitives.generateDeviceKeyset('bob-tablet-new');
    carol = primitives.generateDeviceKeyset('carol-web');
  });

  group('PQCv2 private codec', () {
    const conversation = PqcConversation(id: 41, type: 'private');

    test('round-trips for recipient and sender history', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'maxfiy salom',
        sender: alice,
        recipientDevices: [bob.publicKey],
      );
      expect(payload, startsWith('${PqcV2Wire.privatePrefix}:'));

      final bobResult = await engine.private.decrypt(
        conversation: conversation,
        payload: payload,
        localKeysets: [bob],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect(bobResult, isA<PqcDecoded>());
      expect((bobResult as PqcDecoded).plaintext, 'maxfiy salom');

      final senderResult = await engine.private.decrypt(
        conversation: conversation,
        payload: payload,
        localKeysets: [alice],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect((senderResult as PqcDecoded).plaintext, 'maxfiy salom');
    });

    test(
      'engine interface exposes common private encode/decode operations',
      () async {
        final payload = await engine.encodePrivate(
          conversation: conversation,
          plaintext: 'interface round trip',
          sender: alice,
          recipientDevices: [bob.publicKey],
        );
        final result = await engine.decodePrivate(
          conversation: conversation,
          payload: payload,
          localKeysets: [bob],
          trustedSigningKeysByDevice: _trust(alice),
        );

        expect(result, isA<PqcDecoded>());
        expect((result as PqcDecoded).plaintext, 'interface round trip');
      },
    );

    test('keeps historical keysets readable after rotation', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'old key history',
        sender: alice,
        recipientDevices: [bob.publicKey],
      );
      final result = await engine.private.decrypt(
        conversation: conversation,
        payload: payload,
        localKeysets: [bobRotated, bob],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect((result as PqcDecoded).plaintext, 'old key history');
    });

    test('covers every unique recipient device exactly once', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'multi device',
        sender: alice,
        recipientDevices: [bob.publicKey, carol.publicKey, bob.publicKey],
      );
      final document = _privateDocument(payload);
      final targets = (document['wraps'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((item) => item['target_device_id'])
          .toList();
      expect(targets.toSet(), {'alice-phone', 'bob-tablet', 'carol-web'});
      expect(targets.length, 3);
    });

    test('rejects wrong conversation binding', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'bound',
        sender: alice,
        recipientDevices: [bob.publicKey],
      );
      final result = await engine.private.decrypt(
        conversation: const PqcConversation(id: 42, type: 'private'),
        payload: payload,
        localKeysets: [bob],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect(
        (result as PqcDecodeError).failure,
        PqcDecodeFailure.bindingMismatch,
      );
    });

    test('rejects untrusted sender and signature tampering', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'signed',
        sender: alice,
        recipientDevices: [bob.publicKey],
      );
      final untrusted = await engine.private.decrypt(
        conversation: conversation,
        payload: payload,
        localKeysets: [bob],
        trustedSigningKeysByDevice: const {},
      );
      expect(
        (untrusted as PqcDecodeError).failure,
        PqcDecodeFailure.untrustedSender,
      );

      final document = _privateDocument(payload);
      document['content_ciphertext'] = '${document['content_ciphertext']}AA';
      final tampered = _privatePayload(document);
      final result = await engine.private.decrypt(
        conversation: conversation,
        payload: tampered,
        localKeysets: [bob],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect((result as PqcDecodeError).failure, PqcDecodeFailure.corrupted);
    });

    test('classifies missing local key separately', () async {
      final payload = await engine.private.encrypt(
        conversation: conversation,
        plaintext: 'recover me',
        sender: alice,
        recipientDevices: [bob.publicKey],
      );
      final result = await engine.private.decrypt(
        conversation: conversation,
        payload: payload,
        localKeysets: [carol],
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect((result as PqcDecodeError).failure, PqcDecodeFailure.keyMissing);
    });
  });

  group('PQCv2 group codec', () {
    const conversation = PqcConversation(id: 77, type: 'group');
    late PqcGroupEpoch epoch;

    setUp(() {
      epoch = PqcGroupEpoch(
        epochId: 'epoch-7',
        secretKeyBytes: primitives.randomBytes(32),
      );
    });

    test('wraps epoch and round-trips group messages', () async {
      final wrapped = await engine.group.wrapEpoch(
        conversation: conversation,
        epoch: epoch,
        sender: alice,
        recipient: bob.publicKey,
      );
      final recovered = await engine.group.unwrapEpoch(
        conversation: conversation,
        epochId: epoch.epochId,
        wrappedEpoch: wrapped,
        recipient: bob,
        trustedSigningKeysByDevice: _trust(alice),
      );
      expect(recovered, isNotNull);
      expect(recovered!.secretKeyBytes, epoch.secretKeyBytes);

      final payload = await engine.group.encrypt(
        conversation: conversation,
        plaintext: 'guruh xabari',
        epoch: epoch,
        sender: alice,
      );
      final result = await engine.group.decrypt(
        conversation: conversation,
        payload: payload,
        epochsById: {recovered.epochId: recovered},
        trustedSigningKeysByDevice: _trust(alice),
        requireAuthenticatedSender: true,
      );
      expect((result as PqcDecoded).plaintext, 'guruh xabari');
    });

    test('v2.5 epoch envelope binds every routing field', () async {
      final wrapped = await engine.groupEpochV25.wrapEpoch(
        conversation: conversation,
        epoch: epoch,
        sender: alice,
        recipient: bob.publicKey,
      );
      final recovered = await engine.groupEpochV25.unwrapEpoch(
        conversation: conversation,
        wrappedEpoch: wrapped,
        recipient: bob,
        trustedSigningKeysByDevice: _trust(alice),
        trustedKeysetBindingsByDevice: {
          alice.deviceId: {alice.bindingId},
        },
      );
      expect(recovered?.epochId, epoch.epochId);
      expect(recovered?.secretKeyBytes, epoch.secretKeyBytes);
      expect(
        await engine.groupEpochV25.unwrapEpoch(
          conversation: conversation,
          wrappedEpoch: wrapped,
          recipient: bob,
          trustedSigningKeysByDevice: _trust(alice),
          trustedKeysetBindingsByDevice: {},
        ),
        isNull,
      );

      final document = _decodeUrlDocument(
        wrapped.substring(PqcV2Wire.groupWrapV25Prefix.length + 1),
      );
      document['epoch_id'] = 'replayed-under-another-epoch';
      final tampered =
          '${PqcV2Wire.groupWrapV25Prefix}:${_encodeUrlDocument(document)}';
      expect(
        await engine.groupEpochV25.unwrapEpoch(
          conversation: conversation,
          wrappedEpoch: tampered,
          recipient: bob,
          trustedSigningKeysByDevice: _trust(alice),
          trustedKeysetBindingsByDevice: {
            alice.deviceId: {alice.bindingId},
          },
        ),
        isNull,
      );
    });

    test(
      'keeps legacy group payloads readable but can require sender auth',
      () async {
        final payload = await engine.group.encrypt(
          conversation: conversation,
          plaintext: 'legacy group message',
          epoch: epoch,
        );
        final result = await engine.group.decrypt(
          conversation: conversation,
          payload: payload,
          epochsById: {epoch.epochId: epoch},
        );
        expect((result as PqcDecoded).plaintext, 'legacy group message');

        final rejected = await engine.group.decrypt(
          conversation: conversation,
          payload: payload,
          epochsById: {epoch.epochId: epoch},
          requireAuthenticatedSender: true,
        );
        expect(
          (rejected as PqcDecodeError).failure,
          PqcDecodeFailure.untrustedSender,
        );
      },
    );

    test('rejects missing epoch and modified ciphertext', () async {
      final payload = await engine.group.encrypt(
        conversation: conversation,
        plaintext: 'tamper',
        epoch: epoch,
      );
      final missing = await engine.group.decrypt(
        conversation: conversation,
        payload: payload,
        epochsById: const {},
      );
      expect((missing as PqcDecodeError).failure, PqcDecodeFailure.keyMissing);

      final encoded = payload.substring(PqcV2Wire.groupPrefix.length + 1);
      final document = _decodeUrlDocument(encoded);
      document['mac'] = base64Encode(List<int>.filled(16, 0));
      final tampered =
          '${PqcV2Wire.groupPrefix}:${_encodeUrlDocument(document)}';
      final result = await engine.group.decrypt(
        conversation: conversation,
        payload: tampered,
        epochsById: {epoch.epochId: epoch},
      );
      expect((result as PqcDecodeError).failure, PqcDecodeFailure.corrupted);
    });
  });

  group('PQCv2 attachments', () {
    test('round-trips chunks and rejects tampering', () async {
      final descriptor = engine.attachment.generateDescriptor();
      final encrypted = await engine.attachment.encryptChunk(
        plaintext: utf8.encode('PDF/audio/video bytes'),
        descriptor: descriptor,
        chunkIndex: 3,
      );
      final clear = await engine.attachment.decryptChunk(
        ciphertext: encrypted.ciphertext,
        descriptor: descriptor,
        chunkIndex: 3,
      );
      expect(utf8.decode(clear), 'PDF/audio/video bytes');

      final tampered = encrypted.ciphertext.toList();
      tampered[0] ^= 1;
      await expectLater(
        engine.attachment.decryptChunk(
          ciphertext: tampered,
          descriptor: descriptor,
          chunkIndex: 3,
        ),
        throwsA(anything),
      );
    });

    test(
      'derives stable epoch descriptor and authenticates metadata hash',
      () async {
        final first = await engine.attachment.deriveEpochBoundDescriptor(
          conversationEpochSecret: List<int>.generate(32, (index) => index),
          conversationEpochId: 'epoch-a',
          attachmentId: 'file-a',
          manifestSequence: 4,
        );
        final second = await engine.attachment.deriveEpochBoundDescriptor(
          conversationEpochSecret: List<int>.generate(32, (index) => index),
          conversationEpochId: 'epoch-a',
          attachmentId: 'file-a',
          manifestSequence: 4,
        );
        expect(first.toJson(), second.toJson());

        const manifest = PqcAttachmentManifest(
          filename: 'report.pdf',
          mimeType: 'application/pdf',
          cipherVersion: PqcV2Wire.attachmentCipherVersion,
          chunkSize: 10,
          plaintextSize: 21,
          ciphertextSize: 69,
          totalChunks: 3,
          plaintextSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          fileKeyWrap: 'authenticated-envelope',
          conversationEpochId: 'epoch-a',
          recoveryManifestSequence: 4,
        );
        final hash = engine.attachment.buildManifestSha256(manifest);
        expect(engine.attachment.verifyManifestSha256(manifest, hash), isTrue);

        const changed = PqcAttachmentManifest(
          filename: 'evil.pdf',
          mimeType: 'application/pdf',
          cipherVersion: PqcV2Wire.attachmentCipherVersion,
          chunkSize: 10,
          plaintextSize: 21,
          ciphertextSize: 69,
          totalChunks: 3,
          plaintextSha256:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          fileKeyWrap: 'authenticated-envelope',
          conversationEpochId: 'epoch-a',
          recoveryManifestSequence: 4,
        );
        expect(engine.attachment.verifyManifestSha256(changed, hash), isFalse);
      },
    );
  });
}

Map<String, Set<String>> _trust(PqcDeviceKeyset keyset) => {
  keyset.deviceId: {keyset.signingPublicKeyBase64},
};

Map<String, dynamic> _privateDocument(String payload) {
  return _decodeUrlDocument(
    payload.substring(PqcV2Wire.privatePrefix.length + 1),
  );
}

String _privatePayload(Map<String, dynamic> document) =>
    '${PqcV2Wire.privatePrefix}:${_encodeUrlDocument(document)}';

Map<String, dynamic> _decodeUrlDocument(String encoded) {
  final padded = encoded.padRight(
    encoded.length + ((4 - encoded.length % 4) % 4),
    '=',
  );
  return Map<String, dynamic>.from(
    jsonDecode(utf8.decode(base64Url.decode(padded))) as Map,
  );
}

String _encodeUrlDocument(Map<String, dynamic> document) =>
    base64UrlEncode(utf8.encode(jsonEncode(document))).replaceAll('=', '');
