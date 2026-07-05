// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../core/device/device_identity_service.dart';
import '../../core/device/device_key_service.dart';
import '../../core/device/device_prekey_service.dart';
import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';
import 'chat_crypto_exceptions.dart';
import 'group_key_store.dart';
import 'outbound_message_cache.dart';
import 'peer_prekey_selection_service.dart';
import 'private_session_store.dart';

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
    required DeviceIdentityService deviceIdentityService,
    required DeviceKeyService deviceKeyService,
    required DevicePreKeyService devicePreKeyService,
    required PrivateSessionStore privateSessionStore,
    required OutboundMessageCache outboundMessageCache,
    required GroupKeyProvider groupKeyStore,
    PeerPreKeySelectionService? peerPreKeySelectionService,
    X25519CipherMessageCodec? x25519Codec,
    GroupCipherMessageCodec? groupCodec,
  }) : _x25519Codec =
           x25519Codec ??
           X25519CipherMessageCodec(
             deviceIdentityService: deviceIdentityService,
             deviceKeyService: deviceKeyService,
             devicePreKeyService: devicePreKeyService,
             privateSessionStore: privateSessionStore,
             peerPreKeySelectionService: peerPreKeySelectionService,
           ),
       _outboundMessageCache = outboundMessageCache,
       _groupCodec =
           groupCodec ?? GroupCipherMessageCodec(groupKeyStore: groupKeyStore);

  final X25519CipherMessageCodec _x25519Codec;
  final OutboundMessageCache _outboundMessageCache;
  final GroupCipherMessageCodec _groupCodec;

  @override
  Future<String> compose({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final payload = conversation.isGroup
        ? await _groupCodec.encrypt(
            conversation: conversation,
            plaintext: plaintext,
            usersById: usersById,
          )
        : await _x25519Codec.encrypt(
            currentUserId: currentUserId,
            conversation: conversation,
            plaintext: plaintext,
            usersById: usersById,
          );

    await _outboundMessageCache.storePlaintext(
      payload: payload,
      plaintext: plaintext,
    );
    return payload;
  }
}

class HybridMessageDecoderService implements MessageDecoderService {
  HybridMessageDecoderService({
    required DeviceIdentityService deviceIdentityService,
    required DeviceKeyService deviceKeyService,
    required DevicePreKeyService devicePreKeyService,
    required PrivateSessionStore privateSessionStore,
    required OutboundMessageCache outboundMessageCache,
    required GroupKeyProvider groupKeyStore,
    DemoCipherMessageCodec? demoCodec,
    X25519CipherMessageCodec? x25519Codec,
    GroupCipherMessageCodec? groupCodec,
  }) : _demoCodec = demoCodec ?? DemoCipherMessageCodec(),
       _x25519Codec =
           x25519Codec ??
           X25519CipherMessageCodec(
             deviceIdentityService: deviceIdentityService,
             deviceKeyService: deviceKeyService,
             devicePreKeyService: devicePreKeyService,
             privateSessionStore: privateSessionStore,
           ),
       _outboundMessageCache = outboundMessageCache,
       _groupCodec =
           groupCodec ?? GroupCipherMessageCodec(groupKeyStore: groupKeyStore);

  final DemoCipherMessageCodec _demoCodec;
  final X25519CipherMessageCodec _x25519Codec;
  final OutboundMessageCache _outboundMessageCache;
  final GroupCipherMessageCodec _groupCodec;

  @override
  Future<String> decode({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    final cachedPlaintext = await _outboundMessageCache.readPlaintext(payload);
    if (cachedPlaintext != null) {
      return cachedPlaintext;
    }

    if (payload.startsWith('${X25519CipherMessageCodec.prefix}:') ||
        payload.startsWith('${X25519CipherMessageCodec.sessionPrefix}:') ||
        payload.startsWith('${X25519CipherMessageCodec.previousPrefix}:') ||
        payload.startsWith('${X25519CipherMessageCodec.legacyPrefix}:')) {
      final plaintext = await _x25519Codec.decrypt(
        currentUserId: currentUserId,
        conversation: conversation,
        payload: payload,
        usersById: usersById,
      );
      if (plaintext != '[decrypt-error]') {
        await _outboundMessageCache.storePlaintext(
          payload: payload,
          plaintext: plaintext,
        );
      }
      return plaintext;
    }

    if (payload.startsWith('${GroupCipherMessageCodec.prefix}:')) {
      final plaintext = await _groupCodec.decrypt(
        conversation: conversation,
        payload: payload,
        usersById: usersById,
      );
      if (plaintext != '[decrypt-error]') {
        await _outboundMessageCache.storePlaintext(
          payload: payload,
          plaintext: plaintext,
        );
      }
      return plaintext;
    }

    if (payload.startsWith('${DemoCipherMessageCodec.prefix}:')) {
      final plaintext = await _demoCodec.decrypt(
        conversation: conversation,
        payload: payload,
      );
      if (plaintext != '[decrypt-error]') {
        await _outboundMessageCache.storePlaintext(
          payload: payload,
          plaintext: plaintext,
        );
      }
      return plaintext;
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
    required this.deviceIdentityService,
    required this.deviceKeyService,
    required this.devicePreKeyService,
    required this.privateSessionStore,
    PeerPreKeySelectionService? peerPreKeySelectionService,
    X25519? keyExchange,
    Hkdf? hkdf,
    AesGcm? cipher,
  }) : _keyExchange = keyExchange ?? X25519(),
       _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
       _cipher = cipher ?? AesGcm.with256bits(),
       _peerPreKeySelectionService =
           peerPreKeySelectionService ?? PeerPreKeySelectionService();

  static const prefix = 'x25519:v4';
  static const sessionPrefix = 'session:v1';
  static const previousPrefix = 'x25519:v3';
  static const legacyPrefix = 'x25519:v1';
  static const _maxSkippedRemoteMessages = 64;
  static final _random = Random.secure();

  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;
  final DevicePreKeyService devicePreKeyService;
  final PrivateSessionStore privateSessionStore;
  final X25519 _keyExchange;
  final Hkdf _hkdf;
  final AesGcm _cipher;
  final PeerPreKeySelectionService _peerPreKeySelectionService;

  Future<String> encrypt({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final peerDevice = _resolvePeerDevice(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: usersById,
    );
    final remotePublicKey = SimplePublicKey(
      base64Decode(peerDevice.identityPublicKey),
      type: KeyPairType.x25519,
    );
    final deviceIdentity = await deviceIdentityService.getIdentity();
    final keyMaterial = await deviceKeyService.getOrCreateKeyMaterial();
    final staticKeyPair = await deviceKeyService.getIdentityKeyPair();
    final ephemeralKeyPair = await _keyExchange.newKeyPair();
    final ephemeralKeyPairData = await ephemeralKeyPair.extract();
    final reservedPeerPreKey = await _peerPreKeySelectionService
        .reserveNextPreKey(peerDevice);
    if (reservedPeerPreKey != null) {
      final bootstrapSecretKey = await _derivePreKeyBootstrapSecretKey(
        staticKeyPair: staticKeyPair,
        ephemeralKeyPair: ephemeralKeyPair,
        remoteIdentityPublicKey: remotePublicKey,
        remotePreKeyPublicKey: SimplePublicKey(
          base64Decode(reservedPeerPreKey.publicKey),
          type: KeyPairType.x25519,
        ),
        info: conversation.keyMaterial,
      );
      final rootKey = await _deriveSessionRootKey(
        bootstrapSecretKey,
        info: conversation.keyMaterial,
      );
      final chainKeys = await _deriveSessionChainKeys(
        rootKey: rootKey,
        initiatorSendsFirst: true,
      );
      await privateSessionStore.establishSession(
        conversationId: conversation.id,
        peerDeviceId: peerDevice.deviceId,
        peerIdentityPublicKey: peerDevice.identityPublicKey,
        rootKey: rootKey,
        sendingChainKey: chainKeys.localSendingChainKey,
        receivingChainKey: chainKeys.localReceivingChainKey,
        establishedBy: prefix,
      );
      final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
      final secretBox = await _cipher.encrypt(
        utf8.encode(plaintext),
        secretKey: bootstrapSecretKey,
        nonce: nonce,
      );

      return [
        prefix,
        deviceIdentity.id,
        keyMaterial.publicKey,
        base64Encode(ephemeralKeyPairData.publicKey.bytes),
        reservedPeerPreKey.keyId,
        base64Encode(secretBox.nonce),
        base64Encode(secretBox.cipherText),
        base64Encode(secretBox.mac.bytes),
      ].join(':');
    }

    final bootstrapSecretKey = await _deriveHybridSharedSecretKey(
      staticKeyPair: staticKeyPair,
      ephemeralKeyPair: ephemeralKeyPair,
      remotePublicKey: remotePublicKey,
      info: conversation.keyMaterial,
    );
    final rootKey = await _deriveSessionRootKey(
      bootstrapSecretKey,
      info: conversation.keyMaterial,
    );
    final chainKeys = await _deriveSessionChainKeys(
      rootKey: rootKey,
      initiatorSendsFirst: true,
    );
    await privateSessionStore.establishSession(
      conversationId: conversation.id,
      peerDeviceId: peerDevice.deviceId,
      peerIdentityPublicKey: peerDevice.identityPublicKey,
      rootKey: rootKey,
      sendingChainKey: chainKeys.localSendingChainKey,
      receivingChainKey: chainKeys.localReceivingChainKey,
      establishedBy: previousPrefix,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: bootstrapSecretKey,
      nonce: nonce,
    );

    return [
      previousPrefix,
      deviceIdentity.id,
      keyMaterial.publicKey,
      base64Encode(ephemeralKeyPairData.publicKey.bytes),
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
      if (payload.startsWith('$sessionPrefix:')) {
        final parts = payload.substring(sessionPrefix.length + 1).split(':');
        if (parts.length != 5) {
          return '[decrypt-error]';
        }

        final session = await privateSessionStore.readSession(
          conversationId: conversation.id,
          peerDeviceId: parts[0],
        );
        if (session == null) {
          return '[decrypt-error]';
        }

        final messageKey = await _resolveIncomingSessionMessageKey(
          conversation: conversation,
          peerDeviceId: parts[0],
          counter: int.parse(parts[1]),
          session: session,
        );
        if (messageKey == null) {
          return '[decrypt-error]';
        }
        final clearBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(parts[3]),
            nonce: base64Decode(parts[2]),
            mac: Mac(base64Decode(parts[4])),
          ),
          secretKey: messageKey,
        );
        return utf8.decode(clearBytes);
      }

      if (payload.startsWith('$prefix:')) {
        final parts = payload.substring(prefix.length + 1).split(':');
        if (parts.length != 7) {
          return '[decrypt-error]';
        }

        final senderStaticPublicKey = SimplePublicKey(
          base64Decode(parts[1]),
          type: KeyPairType.x25519,
        );
        final senderEphemeralPublicKey = SimplePublicKey(
          base64Decode(parts[2]),
          type: KeyPairType.x25519,
        );
        final localIdentityKeyPair = await deviceKeyService
            .getIdentityKeyPair();
        final localPreKeyPair = await devicePreKeyService.takePreKeyPair(
          parts[3],
        );
        if (localPreKeyPair == null) {
          return '[decrypt-error]';
        }
        final bootstrapSecretKey =
            await _derivePreKeyBootstrapSecretKeyForReceiver(
              localIdentityKeyPair: localIdentityKeyPair,
              localPreKeyPair: localPreKeyPair,
              senderStaticPublicKey: senderStaticPublicKey,
              senderEphemeralPublicKey: senderEphemeralPublicKey,
              info: conversation.keyMaterial,
            );
        final rootKey = await _deriveSessionRootKey(
          bootstrapSecretKey,
          info: conversation.keyMaterial,
        );
        final chainKeys = await _deriveSessionChainKeys(
          rootKey: rootKey,
          initiatorSendsFirst: false,
        );
        await privateSessionStore.establishSession(
          conversationId: conversation.id,
          peerDeviceId: parts[0],
          peerIdentityPublicKey: parts[1],
          rootKey: rootKey,
          sendingChainKey: chainKeys.localSendingChainKey,
          receivingChainKey: chainKeys.localReceivingChainKey,
          establishedBy: prefix,
        );
        final clearBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(parts[5]),
            nonce: base64Decode(parts[4]),
            mac: Mac(base64Decode(parts[6])),
          ),
          secretKey: bootstrapSecretKey,
        );
        await devicePreKeyService.removePreKey(parts[3]);
        return utf8.decode(clearBytes);
      }

      if (payload.startsWith('$previousPrefix:')) {
        final parts = payload.substring(previousPrefix.length + 1).split(':');
        if (parts.length != 6) {
          return '[decrypt-error]';
        }

        final senderStaticPublicKey = SimplePublicKey(
          base64Decode(parts[1]),
          type: KeyPairType.x25519,
        );
        final senderEphemeralPublicKey = SimplePublicKey(
          base64Decode(parts[2]),
          type: KeyPairType.x25519,
        );
        final localKeyPair = await deviceKeyService.getIdentityKeyPair();
        final bootstrapSecretKey =
            await _deriveHybridSharedSecretKeyForReceiver(
              localKeyPair: localKeyPair,
              senderStaticPublicKey: senderStaticPublicKey,
              senderEphemeralPublicKey: senderEphemeralPublicKey,
              info: conversation.keyMaterial,
            );
        final rootKey = await _deriveSessionRootKey(
          bootstrapSecretKey,
          info: conversation.keyMaterial,
        );
        final chainKeys = await _deriveSessionChainKeys(
          rootKey: rootKey,
          initiatorSendsFirst: false,
        );
        await privateSessionStore.establishSession(
          conversationId: conversation.id,
          peerDeviceId: parts[0],
          peerIdentityPublicKey: parts[1],
          rootKey: rootKey,
          sendingChainKey: chainKeys.localSendingChainKey,
          receivingChainKey: chainKeys.localReceivingChainKey,
          establishedBy: previousPrefix,
        );
        final clearBytes = await _cipher.decrypt(
          SecretBox(
            base64Decode(parts[4]),
            nonce: base64Decode(parts[3]),
            mac: Mac(base64Decode(parts[5])),
          ),
          secretKey: bootstrapSecretKey,
        );
        return utf8.decode(clearBytes);
      }

      final parts = payload.substring(legacyPrefix.length + 1).split(':');
      if (parts.length != 3) {
        return '[decrypt-error]';
      }
      final remotePublicKey = SimplePublicKey(
        base64Decode(
          _resolvePeerDevice(
            currentUserId: currentUserId,
            conversation: conversation,
            usersById: usersById,
          ).identityPublicKey,
        ),
        type: KeyPairType.x25519,
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

  Future<SecretKey> _deriveHybridSharedSecretKey({
    required SimpleKeyPair staticKeyPair,
    required SimpleKeyPair ephemeralKeyPair,
    required SimplePublicKey remotePublicKey,
    required String info,
  }) async {
    final staticSharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: staticKeyPair,
      remotePublicKey: remotePublicKey,
    );
    final ephemeralSharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: remotePublicKey,
    );

    return _deriveCombinedSecretKey(
      firstSecret: staticSharedSecret,
      secondSecret: ephemeralSharedSecret,
      info: info,
    );
  }

  Future<SecretKey> _derivePreKeyBootstrapSecretKey({
    required SimpleKeyPair staticKeyPair,
    required SimpleKeyPair ephemeralKeyPair,
    required SimplePublicKey remoteIdentityPublicKey,
    required SimplePublicKey remotePreKeyPublicKey,
    required String info,
  }) async {
    final sharedSecret1 = await _keyExchange.sharedSecretKey(
      keyPair: staticKeyPair,
      remotePublicKey: remotePreKeyPublicKey,
    );
    final sharedSecret2 = await _keyExchange.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: remoteIdentityPublicKey,
    );
    final sharedSecret3 = await _keyExchange.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: remotePreKeyPublicKey,
    );
    final sharedSecret4 = await _keyExchange.sharedSecretKey(
      keyPair: staticKeyPair,
      remotePublicKey: remoteIdentityPublicKey,
    );

    return _deriveStackedSecretKey(
      secrets: [sharedSecret1, sharedSecret2, sharedSecret3, sharedSecret4],
      info: '$info|prekey-bootstrap',
    );
  }

  Future<SecretKey> _derivePreKeyBootstrapSecretKeyForReceiver({
    required SimpleKeyPair localIdentityKeyPair,
    required SimpleKeyPair localPreKeyPair,
    required SimplePublicKey senderStaticPublicKey,
    required SimplePublicKey senderEphemeralPublicKey,
    required String info,
  }) async {
    final sharedSecret1 = await _keyExchange.sharedSecretKey(
      keyPair: localPreKeyPair,
      remotePublicKey: senderStaticPublicKey,
    );
    final sharedSecret2 = await _keyExchange.sharedSecretKey(
      keyPair: localIdentityKeyPair,
      remotePublicKey: senderEphemeralPublicKey,
    );
    final sharedSecret3 = await _keyExchange.sharedSecretKey(
      keyPair: localPreKeyPair,
      remotePublicKey: senderEphemeralPublicKey,
    );
    final sharedSecret4 = await _keyExchange.sharedSecretKey(
      keyPair: localIdentityKeyPair,
      remotePublicKey: senderStaticPublicKey,
    );

    return _deriveStackedSecretKey(
      secrets: [sharedSecret1, sharedSecret2, sharedSecret3, sharedSecret4],
      info: '$info|prekey-bootstrap',
    );
  }

  Future<SecretKey> _deriveHybridSharedSecretKeyForReceiver({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey senderStaticPublicKey,
    required SimplePublicKey senderEphemeralPublicKey,
    required String info,
  }) async {
    final staticSharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: senderStaticPublicKey,
    );
    final ephemeralSharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: senderEphemeralPublicKey,
    );

    return _deriveCombinedSecretKey(
      firstSecret: staticSharedSecret,
      secondSecret: ephemeralSharedSecret,
      info: info,
    );
  }

  Future<SecretKey> _deriveCombinedSecretKey({
    required SecretKey firstSecret,
    required SecretKey secondSecret,
    required String info,
  }) async {
    final combinedSecretBytes = [
      ...await firstSecret.extractBytes(),
      ...await secondSecret.extractBytes(),
    ];
    return _hkdf.deriveKey(
      secretKey: SecretKey(combinedSecretBytes),
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-x25519-hybrid-message-key'),
    );
  }

  Future<SecretKey> _deriveStackedSecretKey({
    required List<SecretKey> secrets,
    required String info,
  }) async {
    final combinedSecretBytes = <int>[];
    for (final secret in secrets) {
      combinedSecretBytes.addAll(await secret.extractBytes());
    }
    return _hkdf.deriveKey(
      secretKey: SecretKey(combinedSecretBytes),
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-x25519-prekey-message-key'),
    );
  }

  Future<String> _deriveSessionRootKey(
    SecretKey bootstrapSecretKey, {
    required String info,
  }) async {
    final rootKey = await _hkdf.deriveKey(
      secretKey: bootstrapSecretKey,
      nonce: utf8.encode(info),
      info: utf8.encode('pqc-chat-x25519-session-root'),
    );
    return base64Encode(await rootKey.extractBytes());
  }

  Future<SecretKey> _deriveSessionMessageKey({required String chainKey}) async {
    return _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(chainKey)),
      nonce: utf8.encode('session-message'),
      info: utf8.encode('pqc-chat-x25519-session-message-key'),
    );
  }

  Future<String> _deriveNextSessionChainKey({required String chainKey}) async {
    final nextChainKey = await _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(chainKey)),
      nonce: utf8.encode('session-chain-next'),
      info: utf8.encode('pqc-chat-x25519-session-chain-key'),
    );
    return base64Encode(await nextChainKey.extractBytes());
  }

  Future<_PrivateSessionChainKeys> _deriveSessionChainKeys({
    required String rootKey,
    required bool initiatorSendsFirst,
  }) async {
    final initiatorSending = await _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(rootKey)),
      nonce: utf8.encode('initiator-send'),
      info: utf8.encode('pqc-chat-x25519-session-initial-chain'),
    );
    final responderSending = await _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(rootKey)),
      nonce: utf8.encode('responder-send'),
      info: utf8.encode('pqc-chat-x25519-session-initial-chain'),
    );
    final initiatorSendingBytes = base64Encode(
      await initiatorSending.extractBytes(),
    );
    final responderSendingBytes = base64Encode(
      await responderSending.extractBytes(),
    );
    if (initiatorSendsFirst) {
      return _PrivateSessionChainKeys(
        localSendingChainKey: initiatorSendingBytes,
        localReceivingChainKey: responderSendingBytes,
      );
    }
    return _PrivateSessionChainKeys(
      localSendingChainKey: responderSendingBytes,
      localReceivingChainKey: initiatorSendingBytes,
    );
  }

  Future<SecretKey?> _resolveIncomingSessionMessageKey({
    required Conversation conversation,
    required String peerDeviceId,
    required int counter,
    required PrivateSessionState session,
  }) async {
    final cachedSkippedMessageKey =
        session.skippedRemoteMessageKeys[counter.toString()];
    if (cachedSkippedMessageKey != null) {
      final nextSkippedKeys = Map<String, String>.from(
        session.skippedRemoteMessageKeys,
      )..remove(counter.toString());
      await privateSessionStore.updateSession(
        session.copyWith(skippedRemoteMessageKeys: nextSkippedKeys),
      );
      return SecretKey(base64Decode(cachedSkippedMessageKey));
    }

    if (counter < session.nextRemoteCounter) {
      return null;
    }

    if (counter - session.nextRemoteCounter > _maxSkippedRemoteMessages) {
      return null;
    }

    var workingChainKey = session.receivingChainKey;
    var workingCounter = session.nextRemoteCounter;
    final skippedKeys = Map<String, String>.from(
      session.skippedRemoteMessageKeys,
    );

    while (workingCounter < counter) {
      final skippedMessageKey = await _deriveSessionMessageKey(
        chainKey: workingChainKey,
      );
      skippedKeys[workingCounter.toString()] = base64Encode(
        await skippedMessageKey.extractBytes(),
      );
      if (skippedKeys.length > _maxSkippedRemoteMessages) {
        final sortedKeys = skippedKeys.keys.toList()
          ..sort((a, b) => int.parse(a).compareTo(int.parse(b)));
        skippedKeys.remove(sortedKeys.first);
      }
      workingChainKey = await _deriveNextSessionChainKey(
        chainKey: workingChainKey,
      );
      workingCounter += 1;
    }

    final messageKey = await _deriveSessionMessageKey(
      chainKey: workingChainKey,
    );
    final nextReceivingChainKey = await _deriveNextSessionChainKey(
      chainKey: workingChainKey,
    );
    await privateSessionStore.updateSession(
      session.copyWith(
        receivingChainKey: nextReceivingChainKey,
        nextRemoteCounter: counter + 1,
        skippedRemoteMessageKeys: skippedKeys,
      ),
    );
    return messageKey;
  }

  AppUserDevice _resolvePeerDevice({
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
    return device;
  }
}

class _PrivateSessionChainKeys {
  const _PrivateSessionChainKeys({
    required this.localSendingChainKey,
    required this.localReceivingChainKey,
  });

  final String localSendingChainKey;
  final String localReceivingChainKey;
}
