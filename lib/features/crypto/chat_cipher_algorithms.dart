import '../../core/device/device_identity_service.dart';
import '../../core/device/device_key_service.dart';
import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import '../../core/device/device_prekey_service.dart';
import '../../core/models/conversation.dart';
import 'chat_cipher_service.dart';
import 'chat_crypto_context.dart';
import 'group_key_store.dart';
import 'message_codec.dart';
import 'peer_prekey_selection_service.dart';
import 'private_session_store.dart';

class GroupChatCipherAlgorithm implements ChatCipherAlgorithm {
  GroupChatCipherAlgorithm({
    required GroupKeyProvider groupKeyStore,
    GroupCipherMessageCodec? codec,
  }) : _codec = codec ?? GroupCipherMessageCodec(groupKeyStore: groupKeyStore);

  final GroupCipherMessageCodec _codec;

  @override
  bool supportsConversation(Conversation conversation) => conversation.isGroup;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${GroupCipherMessageCodec.prefix}:');

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) {
    return _codec.encrypt(
      conversation: context.conversation,
      plaintext: plaintext,
      usersById: context.usersById,
    );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) {
    return _codec.decrypt(
      conversation: context.conversation,
      payload: payload,
      usersById: context.usersById,
    );
  }
}

class LegacyPrivateTransportDecryptAlgorithm implements ChatCipherAlgorithm {
  LegacyPrivateTransportDecryptAlgorithm({
    required DeviceIdentityService deviceIdentityService,
    required DeviceKeyService deviceKeyService,
    required DevicePqcKeyService devicePqcKeyService,
    required DevicePqcSigningKeyService devicePqcSigningKeyService,
    required DevicePreKeyService devicePreKeyService,
    required PrivateSessionStore privateSessionStore,
    PeerPreKeySelectionService? peerPreKeySelectionService,
    X25519CipherMessageCodec? codec,
  }) : _codec =
           codec ??
           X25519CipherMessageCodec(
             deviceIdentityService: deviceIdentityService,
             deviceKeyService: deviceKeyService,
             devicePqcKeyService: devicePqcKeyService,
             devicePqcSigningKeyService: devicePqcSigningKeyService,
             devicePreKeyService: devicePreKeyService,
             privateSessionStore: privateSessionStore,
             peerPreKeySelectionService: peerPreKeySelectionService,
           );

  final X25519CipherMessageCodec _codec;

  @override
  bool supportsConversation(Conversation conversation) => false;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${X25519CipherMessageCodec.hybridPrefix}:') ||
      payload.startsWith('${X25519CipherMessageCodec.hybridPreviousPrefix}:') ||
      payload.startsWith('${X25519CipherMessageCodec.prefix}:') ||
      payload.startsWith('${X25519CipherMessageCodec.sessionPrefix}:') ||
      payload.startsWith('${X25519CipherMessageCodec.previousPrefix}:') ||
      payload.startsWith('${X25519CipherMessageCodec.legacyPrefix}:');

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) {
    return _codec.encrypt(
      currentUserId: context.currentUserId,
      conversation: context.conversation,
      plaintext: plaintext,
      usersById: context.usersById,
    );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) {
    return _codec.decrypt(
      currentUserId: context.currentUserId,
      conversation: context.conversation,
      payload: payload,
      usersById: context.usersById,
    );
  }
}

class StablePrivateChatAlgorithm implements ChatCipherAlgorithm {
  StablePrivateChatAlgorithm({DemoCipherMessageCodec? codec})
    : _codec = codec ?? DemoCipherMessageCodec();

  final DemoCipherMessageCodec _codec;

  @override
  bool supportsConversation(Conversation conversation) => !conversation.isGroup;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${DemoCipherMessageCodec.prefix}:');

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) {
    return _codec.encrypt(
      conversation: context.conversation,
      plaintext: plaintext,
    );
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) {
    return _codec.decrypt(conversation: context.conversation, payload: payload);
  }
}
