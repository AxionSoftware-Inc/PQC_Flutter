import '../../../core/database/app_database.dart';
import '../../../core/models/app_user.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/conversation.dart';
import '../../../core/storage/local_data_protector.dart';
import '../../crypto/chat_cipher_service.dart';
import '../../security/key_verification_service.dart';
import '../application/chat_facade.dart';
import '../application/chat_local_store.dart';
import '../application/chat_models.dart';
import '../application/chat_services.dart';
import 'chat_remote_data_source.dart';
import 'chat_realtime_service.dart';
import 'outbox_store.dart';
import 'private_conversation_security_coordinator.dart';

class ChatRepository {
  ChatRepository({
    required ChatRemoteDataSource remoteDataSource,
    required ChatCipherService cipherService,
    required KeyVerificationService keyVerificationService,
    required PrivateConversationSecurityCoordinator
    privateConversationSecurityCoordinator,
    AppDatabase? database,
    LocalDataProtector? localDataProtector,
    ChatRealtimeService? realtimeService,
    OutboxStore? outboxStore,
  }) : _facade = ChatFacade(
         remoteDataSource: remoteDataSource,
         realtimeService: realtimeService,
         outboxStore:
             outboxStore ??
             OutboxStore(
               database: database ?? AppDatabase(),
               localDataProtector: localDataProtector ?? LocalDataProtector(),
             ),
         localStore: ChatLocalStore(
           database: database ?? AppDatabase(),
           localDataProtector: localDataProtector ?? LocalDataProtector(),
         ),
         trustService: ChatTrustService(
           keyVerificationService: keyVerificationService,
           privateConversationSecurityCoordinator:
               privateConversationSecurityCoordinator,
         ),
         cryptoService: ChatCryptoService(cipherService: cipherService),
       );

  final ChatFacade _facade;

  void setActiveWorkspaceId(int workspaceId) {
    _facade.switchWorkspaceContext(workspaceId);
  }

  Future<List<Conversation>> fetchConversations({
    required int currentUserId,
  }) async {
    final state = await _facade.loadChatList(currentUserId: currentUserId);
    return state.conversations;
  }

  Future<List<ChatMessage>> fetchMessages({
    required Conversation conversation,
    required int currentUserId,
  }) async {
    final state = await _facade.loadConversationMessages(
      conversation: conversation,
      currentUserId: currentUserId,
    );
    return state.messages;
  }

  Future<ChatMessage> sendMessage(
    Conversation conversation, {
    required int currentUserId,
    required String text,
    String messageType = 'text',
    List<PendingAttachmentUpload> attachments = const [],
  }) {
    return _facade.sendMessage(
      SendMessageCommand(
        conversation: conversation,
        currentUserId: currentUserId,
        text: text,
        messageType: messageType,
        attachments: attachments,
      ),
    );
  }

  Future<void> retryMessage({
    required Conversation conversation,
    required int currentUserId,
    required String clientMessageId,
  }) {
    return _facade.retryMessage(
      conversation: conversation,
      currentUserId: currentUserId,
      clientMessageId: clientMessageId,
    );
  }

  Future<void> verifyConversationPeerKey({
    required int currentUserId,
    required Conversation conversation,
  }) {
    return _facade.verifyConversationPeerKey(
      currentUserId: currentUserId,
      conversation: conversation,
    );
  }

  Future<Map<int, UserKeyTrust>> buildUserTrustMap() {
    return _facade.buildUserTrustMap();
  }

  Future<ConversationKeyTrust> getConversationTrust({
    required int currentUserId,
    required Conversation conversation,
  }) async {
    final state = await _facade.loadConversationTrust(
      currentUserId: currentUserId,
      conversation: conversation,
    );
    return state.trust;
  }

  Future<Conversation> openPrivateConversation(int otherUserId) {
    return _facade.openPrivateConversation(otherUserId);
  }

  Future<List<AppUser>> fetchUsers() {
    return _facade.fetchUsers();
  }
}
