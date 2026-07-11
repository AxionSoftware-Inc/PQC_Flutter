import '../../core/device/device_identity_service.dart';
import '../../core/device/device_pqc_key_service.dart';
import '../../core/device/device_pqc_signing_key_service.dart';
import '../../core/models/conversation.dart';
import 'durability/key_material_registry.dart';
import 'chat_cipher_service.dart';
import 'chat_crypto_context.dart';
import 'group_key_store.dart';
import 'message_codec.dart';

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

class PqcPrivateChatAlgorithm implements ChatCipherAlgorithm {
  PqcPrivateChatAlgorithm({
    required DeviceIdentityService deviceIdentityService,
    required DevicePqcKeyService devicePqcKeyService,
    required DevicePqcSigningKeyService devicePqcSigningKeyService,
    KeyMaterialRegistry? keyMaterialRegistry,
    PqcPrivateMessageCodec? codec,
  }) : _codec =
           codec ??
           PqcPrivateMessageCodec(
             deviceIdentityService: deviceIdentityService,
             devicePqcKeyService: devicePqcKeyService,
             devicePqcSigningKeyService: devicePqcSigningKeyService,
             keyMaterialRegistry: keyMaterialRegistry,
           );

  final PqcPrivateMessageCodec _codec;

  @override
  bool supportsConversation(Conversation conversation) => !conversation.isGroup;

  @override
  bool canDecrypt(String payload) =>
      payload.startsWith('${PqcPrivateMessageCodec.prefix}:');

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
