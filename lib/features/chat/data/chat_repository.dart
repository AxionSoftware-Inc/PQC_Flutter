import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../crypto/chat_crypto_exceptions.dart';
import '../../crypto/message_codec.dart';
import '../../crypto/private_session_store.dart';
import '../../security/key_verification_service.dart';
import 'chat_remote_data_source.dart';

class ChatRepository {
  ChatRepository({
    required this.remoteDataSource,
    required this.composerService,
    required this.decoderService,
    required this.privateSessionStore,
    required this.keyVerificationService,
  });

  final ChatRemoteDataSource remoteDataSource;
  final MessageComposerService composerService;
  final MessageDecoderService decoderService;
  final PrivateSessionStore privateSessionStore;
  final KeyVerificationService keyVerificationService;
  final Map<int, AppUser> _usersById = {};

  Future<List<AppUser>> fetchUsers() async {
    final users = await remoteDataSource.fetchUsers();
    _usersById
      ..clear()
      ..addEntries(users.map((user) => MapEntry(user.id, user)));
    return users;
  }

  Future<List<Conversation>> fetchConversations({
    required int currentUserId,
  }) async {
    await _ensureUsersLoaded();
    final conversations = await remoteDataSource.fetchConversations();
    final decoded = <Conversation>[];
    for (final conversation in conversations) {
      final preview = conversation.lastMessagePreview.isEmpty
          ? ''
          : await decoderService.decode(
              currentUserId: currentUserId,
              conversation: conversation,
              payload: conversation.lastMessagePreview,
              usersById: _usersById,
            );
      decoded.add(
        conversation.copyWith(
          lastMessagePreview: preview.length > 80
              ? preview.substring(0, 80)
              : preview,
        ),
      );
    }
    return decoded;
  }

  Future<Conversation> openPrivateConversation(int otherUserId) =>
      remoteDataSource.openPrivateConversation(otherUserId);

  Future<List<ChatMessage>> fetchMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    await _ensureUsersLoaded();
    final messages = await remoteDataSource.fetchMessages(conversation.id);
    final decoded = <ChatMessage>[];
    for (final message in messages) {
      decoded.add(
        ChatMessage(
          id: message.id,
          conversationId: message.conversationId,
          senderId: message.senderId,
          senderName: message.senderName,
          body: await decoderService.decode(
            currentUserId: currentUserId,
            conversation: conversation,
            payload: message.body,
            usersById: _usersById,
          ),
          createdAt: message.createdAt,
        ),
      );
    }
    return decoded;
  }

  Future<ChatMessage> sendMessage(
    Conversation conversation, {
    required int currentUserId,
    required String text,
  }) async {
    await _ensureUsersLoaded();
    await _guardPrivateConversationTrust(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    await _preparePrivatePeerPreKey(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    final payload = await composerService.compose(
      currentUserId: currentUserId,
      conversation: conversation,
      plaintext: text,
      usersById: _usersById,
    );
    final message = await remoteDataSource.sendMessage(
      conversation.id,
      payload,
    );
    return ChatMessage(
      id: message.id,
      conversationId: message.conversationId,
      senderId: message.senderId,
      senderName: message.senderName,
      body: await decoderService.decode(
        currentUserId: currentUserId,
        conversation: conversation,
        payload: message.body,
        usersById: _usersById,
      ),
      createdAt: message.createdAt,
    );
  }

  Future<void> _ensureUsersLoaded() async {
    if (_usersById.isNotEmpty) {
      return;
    }
    await fetchUsers();
  }

  Future<Map<int, UserKeyTrust>> buildUserTrustMap() async {
    await _ensureUsersLoaded();
    return keyVerificationService.buildUserTrustMap(_usersById.values);
  }

  Future<ConversationKeyTrust> getConversationTrust({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    await _ensureUsersLoaded();
    return keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
  }

  Future<void> verifyConversationPeerKey({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    await _ensureUsersLoaded();
    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
    final peerUser = trust.peerUser;
    if (peerUser == null) {
      return;
    }
    await keyVerificationService.verifyUser(peerUser);
  }

  Future<void> _preparePrivatePeerPreKey({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    if (conversation.isGroup) {
      return;
    }

    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    final peerUser = _usersById[peerUserId];
    final peerDevice = peerUser?.preferredX25519Device;
    if (peerUser == null || peerDevice == null) {
      return;
    }

    final claimedPreKey = await remoteDataSource.claimPreKey(
      userId: peerUser.id,
      deviceId: peerDevice.deviceId,
    );
    final nextPreKeys = claimedPreKey == null
        ? const <AppUserPreKey>[]
        : [
            AppUserPreKey(
              keyId: claimedPreKey.keyId,
              publicKey: claimedPreKey.publicKey,
            ),
          ];

    final updatedDevices = peerUser.devices.map((device) {
      if (device.deviceId != peerDevice.deviceId) {
        return device;
      }
      return device.copyWith(preKeys: nextPreKeys);
    }).toList();

    _usersById[peerUser.id] = peerUser.copyWith(devices: updatedDevices);
  }

  Future<void> _guardPrivateConversationTrust({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    if (conversation.isGroup) {
      return;
    }

    final trust = await keyVerificationService.getConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
      usersById: _usersById,
    );
    if (trust.hasKeyChanged) {
      throw ChatEncryptionException(
        '${trust.peerUser?.displayName ?? 'Peer'} key changed. Verify the new key before sending more private messages.',
      );
    }
  }
}
