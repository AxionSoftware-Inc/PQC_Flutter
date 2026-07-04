// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/device/device_key_service.dart';
import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';
import 'chat_crypto_exceptions.dart';
import 'group_key_store.dart';

abstract class MessageComposerService {
  Future<String> compose({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  });
}

abstract class MessageDecoderService {
  Future<String> decode({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  });
}

class HybridMessageComposerService implements MessageComposerService {
  HybridMessageComposerService({
    required DeviceKeyService deviceKeyService,
    required GroupKeyProvider groupKeyStore,
    X25519CipherMessageCodec? x25519Codec,
    GroupCipherMessageCodec? groupCodec,
  }) : _x25519Codec =
           x25519Codec ??
           X25519CipherMessageCodec(deviceKeyService: deviceKeyService),
       _groupCodec =
           groupCodec ?? GroupCipherMessageCodec(groupKeyStore: groupKeyStore);

  final X25519CipherMessageCodec _x25519Codec;
  final GroupCipherMessageCodec _groupCodec;

  @override
  Future<String> compose({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    if (conversation.isGroup) {
      return _groupCodec.encrypt(
        conversation: conversation,
        plaintext: plaintext,
        usersById: usersById,
      );
    }

    return _x25519Codec.encrypt(
      currentUserId: currentUserId,
      conversation: conversation,
      plaintext: plaintext,
      usersById: usersById,
    );
  }
}

class HybridMessageDecoderService implements MessageDecoderService {
  HybridMessageDecoderService({
    required DeviceKeyService deviceKeyService,
    required GroupKeyProvider groupKeyStore,
    DemoCipherMessageCodec? demoCodec,
    X25519CipherMessageCodec? x25519Codec,
    GroupCipherMessageCodec? groupCodec,
  }) : _demoCodec = demoCodec ?? DemoCipherMessageCodec(),
       _x25519Codec =
           x25519Codec ??
           X25519CipherMessageCodec(deviceKeyService: deviceKeyService),
       _groupCodec =
           groupCodec ?? GroupCipherMessageCodec(groupKeyStore: groupKeyStore);

  final DemoCipherMessageCodec _demoCodec;
  final X25519CipherMessageCodec _x25519Codec;
  final GroupCipherMessageCodec _groupCodec;

  @override
  Future<String> decode({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    if (payload.startsWith('${X25519CipherMessageCodec.prefix}:')) {
      return _x25519Codec.decrypt(
        currentUserId: currentUserId,
        conversation: conversation,
        payload: payload,
        usersById: usersById,
      );
    }

    if (payload.startsWith('${GroupCipherMessageCodec.prefix}:')) {
      return _groupCodec.decrypt(
        conversation: conversation,
        payload: payload,
        usersById: usersById,
      );
    }

    if (payload.startsWith('${DemoCipherMessageCodec.prefix}:')) {
      return _demoCodec.decrypt(conversation: conversation, payload: payload);
    }

    return payload;
  }
}

class DemoCipherMessageCodec {
  DemoCipherMessageCodec();

  static const prefix = 'enc:v1';
  static const _appSecret = 'pqc-chat-demo-master-secret-v1';

  final AesGcm _algorithm = AesGcm.with256bits();
  final Sha256 _sha256 = Sha256();

  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
  }) async {
    if (!payload.startsWith('$prefix:')) {
      return payload;
    }

    try {
      final parts = payload.substring(prefix.length + 1).split(':');
      if (parts.length != 3) {
        return '[decrypt-error]';
      }

      final nonce = base64Decode(parts[0]);
      final cipherText = base64Decode(parts[1]);
      final macBytes = base64Decode(parts[2]);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));

      for (final keyMaterial in _candidateKeyMaterials(conversation)) {
        try {
          final secretKey = await _deriveSecretKey(keyMaterial);
          final clearBytes = await _algorithm.decrypt(
            secretBox,
            secretKey: secretKey,
          );
          return utf8.decode(clearBytes);
        } catch (_) {
          continue;
        }
      }
      return '[decrypt-error]';
    } catch (_) {
      return '[decrypt-error]';
    }
  }

  Future<SecretKey> _deriveSecretKey(String keyMaterial) async {
    final digest = await _sha256.hash(utf8.encode('$_appSecret|$keyMaterial'));
    return SecretKey(digest.bytes);
  }

  Iterable<String> _candidateKeyMaterials(Conversation conversation) sync* {
    yield '${conversation.id}|${conversation.type}|stable';
    yield conversation.keyMaterial;

    if (!conversation.isGroup) {
      return;
    }

    final participants = [...conversation.participantIds]..sort();
    final totalMasks = 1 << participants.length;
    for (var mask = 0; mask < totalMasks; mask++) {
      final subset = <int>[];
      for (var index = 0; index < participants.length; index++) {
        if ((mask & (1 << index)) != 0) {
          subset.add(participants[index]);
        }
      }
      if (subset.length >= 2) {
        yield '${conversation.id}|${conversation.type}|${subset.join(",")}';
      }
    }
  }
}

class GroupCipherMessageCodec {
  GroupCipherMessageCodec({
    required GroupKeyProvider groupKeyStore,
    AesGcm? cipher,
  }) : _groupKeyStore = groupKeyStore,
       _cipher = cipher ?? AesGcm.with256bits();

  static const prefix = 'group:v1';
  static final _random = Random.secure();

  final GroupKeyProvider _groupKeyStore;
  final AesGcm _cipher;

  Future<String> encrypt({
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final keyMaterial = await _groupKeyStore.getOrCreateKey(
      conversation: conversation,
      usersById: usersById,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyMaterial.secretKeyBytes),
      nonce: nonce,
    );

    return [
      prefix,
      keyMaterial.keyId,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      final parts = payload.substring(prefix.length + 1).split(':');
      if (parts.length != 4) {
        return '[decrypt-error]';
      }

      final keyMaterial = await _groupKeyStore.getExistingKey(
        conversation: conversation,
        usersById: usersById,
        requestedKeyId: parts[0],
      );
      if (keyMaterial == null) {
        return '[decrypt-error]';
      }

      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[2]),
          nonce: base64Decode(parts[1]),
          mac: Mac(base64Decode(parts[3])),
        ),
        secretKey: SecretKey(keyMaterial.secretKeyBytes),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '[decrypt-error]';
    }
  }
}

class X25519CipherMessageCodec {
  X25519CipherMessageCodec({
    required this.deviceKeyService,
    X25519? keyExchange,
    Hkdf? hkdf,
    AesGcm? cipher,
  }) : _keyExchange = keyExchange ?? X25519(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _cipher = cipher ?? AesGcm.with256bits();

  static const prefix = 'x25519:v1';
  static final _random = Random.secure();

  final DeviceKeyService deviceKeyService;
  final X25519 _keyExchange;
  final Hkdf _hkdf;
  final AesGcm _cipher;

  Future<String> encrypt({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final remotePublicKey = _resolvePeerPublicKey(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    final localKeyPair = await deviceKeyService.getIdentityKeyPair();
    final secretKey = await _deriveSharedSecretKey(
      localKeyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
      info: conversation.keyMaterial,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    return [
      prefix,
      base64Encode(secretBox.nonce),
      base64Encode(secretBox.cipherText),
      base64Encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<String> decrypt({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      final parts = payload.substring(prefix.length + 1).split(':');
      if (parts.length != 3) {
        return '[decrypt-error]';
      }
      final remotePublicKey = _resolvePeerPublicKey(
        currentUserId: currentUserId,
        conversation: conversation,
        usersById: usersById,
      );
      final localKeyPair = await deviceKeyService.getIdentityKeyPair();
      final secretKey = await _deriveSharedSecretKey(
        localKeyPair: localKeyPair,
        remotePublicKey: remotePublicKey,
        info: conversation.keyMaterial,
      );
      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(parts[1]),
          nonce: base64Decode(parts[0]),
          mac: Mac(base64Decode(parts[2])),
        ),
        secretKey: secretKey,
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '[decrypt-error]';
    }
  }

  Future<SecretKey> _deriveSharedSecretKey({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
    required String info,
  }) async {
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-x25519-message-key'),
    );
  }

  SimplePublicKey _resolvePeerPublicKey({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) {
    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    final peer = usersById[peerUserId];
    final device = peer?.preferredX25519Device;
    if (peer == null || device == null) {
      throw ChatEncryptionException(
        '${peer?.displayName ?? 'Other user'} hali yangi build bilan login qilmagan. U device public key yuborishi uchun ilovani bir marta ochib kirsin.',
      );
    }
    return SimplePublicKey(
      base64Decode(device.identityPublicKey),
      type: KeyPairType.x25519,
    );
  }
}
