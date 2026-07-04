import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../crypto/message_codec.dart';
import 'chat_remote_data_source.dart';

class ChatRepository {
  ChatRepository({
    required this.remoteDataSource,
    required this.composerService,
    required this.decoderService,
  });

  final ChatRemoteDataSource remoteDataSource;
  final MessageComposerService composerService;
  final MessageDecoderService decoderService;
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
}
