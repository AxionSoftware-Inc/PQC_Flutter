import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/features/chat/data/chat_remote_data_source.dart';
import 'package:pqc_chat_app/features/chat/data/chat_repository.dart';
import 'package:pqc_chat_app/features/chat/data/outbox_store.dart';
import 'package:pqc_chat_app/features/chat/data/private_conversation_security_coordinator.dart';
import 'package:pqc_chat_app/features/crypto/chat_cipher_service.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_context.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_exceptions.dart';
import 'package:pqc_chat_app/features/security/key_verification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final keyVerificationService = _FakeKeyVerificationService(
    const ConversationKeyTrust(
      isAvailable: true,
      isEnterpriseReady: false,
      isVerified: false,
      isEnterpriseVerified: false,
      hasKeyChanged: true,
      hasEnterpriseKeyChanged: true,
      fingerprint: 'dead beef',
      pqcFingerprint: null,
      signingFingerprint: null,
      peerUser: AppUser(
        id: 2,
        username: 'bob',
        displayName: 'Bob',
        devices: [],
      ),
    ),
  );
  test('private send is blocked when verified peer key changed', () async {
    final remote = _FakeChatRemoteDataSource();
    final repository = ChatRepository(
      remoteDataSource: remote,
      cipherService: _FakeChatCipherService(),
      keyVerificationService: keyVerificationService,
      privateConversationSecurityCoordinator:
          PrivateConversationSecurityCoordinator(
            remoteDataSource: remote,
            keyVerificationService: keyVerificationService,
          ),
      outboxStore: OutboxStore(),
    );

    await repository.fetchUsers();

    await expectLater(
      () => repository.sendMessage(
        _privateConversation,
        currentUserId: 1,
        text: 'blocked',
      ),
      throwsA(isA<ChatEncryptionException>()),
    );
  });

  test(
    'send delegates payload handling to the routed cipher service',
    () async {
      final remote = _FakeChatRemoteDataSource();
      final cipherService = _FakeChatCipherService();
      final repository = ChatRepository(
        remoteDataSource: remote,
        cipherService: cipherService,
        keyVerificationService: _FakeKeyVerificationService(
          const ConversationKeyTrust(
            isAvailable: true,
            isEnterpriseReady: false,
            isVerified: false,
            isEnterpriseVerified: false,
            hasKeyChanged: false,
            hasEnterpriseKeyChanged: false,
            fingerprint: 'dead beef',
            pqcFingerprint: null,
            signingFingerprint: null,
            peerUser: AppUser(
              id: 2,
              username: 'bob',
              displayName: 'Bob',
              devices: [],
            ),
          ),
        ),
        privateConversationSecurityCoordinator:
            _NoopPrivateConversationSecurityCoordinator(),
        outboxStore: OutboxStore(),
      );

      await repository.fetchUsers();

      final sent = await repository.sendMessage(
        _privateConversation,
        currentUserId: 1,
        text: 'hello',
      );

      expect(cipherService.lastEncryptedPlaintext, 'hello');
      expect(cipherService.lastDecryptPayload, 'cipher::hello');
      expect(sent.body, 'decoded::cipher::hello');
    },
  );
}

const _users = [
  AppUser(id: 1, username: 'alice', displayName: 'Alice', devices: []),
  AppUser(id: 2, username: 'bob', displayName: 'Bob', devices: []),
];

final _privateConversation = Conversation(
  id: 2,
  type: 'private',
  title: '',
  participantIds: const [1, 2],
  lastMessagePreview: '',
  updatedAt: DateTime.parse('2026-07-04T00:00:00Z'),
  createdAt: DateTime.parse('2026-07-04T00:00:00Z'),
);

class _FakeChatRemoteDataSource extends ChatRemoteDataSource {
  _FakeChatRemoteDataSource() : super(apiClient: ApiClient());

  @override
  Future<List<AppUser>> fetchUsers() async => _users;

  @override
  Future<ClaimedAppUserPreKey?> claimPreKey({
    required int userId,
    required String deviceId,
  }) async {
    return null;
  }

  @override
  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    String clientMessageId = '',
  }) async {
    return ChatMessage(
      id: 1,
      conversationId: conversationId,
      senderId: 1,
      senderName: 'Alice',
      body: body,
      createdAt: DateTime.parse('2026-07-04T00:00:00Z'),
      clientMessageId: clientMessageId,
    );
  }
}

class _FakeChatCipherService implements ChatCipherService {
  String? lastEncryptedPlaintext;
  String? lastDecryptPayload;

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    lastEncryptedPlaintext = plaintext;
    return 'cipher::$plaintext';
  }

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    lastDecryptPayload = payload;
    return 'decoded::$payload';
  }
}

class _FakeKeyVerificationService extends KeyVerificationService {
  _FakeKeyVerificationService(this.trust);

  final ConversationKeyTrust trust;

  @override
  Future<ConversationKeyTrust> getConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    return trust;
  }
}

class _NoopPrivateConversationSecurityCoordinator
    extends PrivateConversationSecurityCoordinator {
  _NoopPrivateConversationSecurityCoordinator()
    : super(
        remoteDataSource: _FakeChatRemoteDataSource(),
        keyVerificationService: _FakeKeyVerificationService(
          const ConversationKeyTrust(
            isAvailable: true,
            isEnterpriseReady: false,
            isVerified: false,
            isEnterpriseVerified: false,
            hasKeyChanged: false,
            hasEnterpriseKeyChanged: false,
            fingerprint: null,
            pqcFingerprint: null,
            signingFingerprint: null,
            peerUser: null,
          ),
        ),
      );

  @override
  Future<void> prepareForSend({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    required void Function(AppUser user) onUserUpdated,
  }) async {}
}
