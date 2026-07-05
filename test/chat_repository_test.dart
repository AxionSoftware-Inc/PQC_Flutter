import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/features/chat/data/chat_remote_data_source.dart';
import 'package:pqc_chat_app/features/chat/data/chat_repository.dart';
import 'package:pqc_chat_app/features/crypto/chat_crypto_exceptions.dart';
import 'package:pqc_chat_app/features/crypto/message_codec.dart';
import 'package:pqc_chat_app/features/crypto/private_session_store.dart';
import 'package:pqc_chat_app/features/security/key_verification_service.dart';

void main() {
  test('private send is blocked when verified peer key changed', () async {
    final remote = _FakeChatRemoteDataSource();
    final repository = ChatRepository(
      remoteDataSource: remote,
      composerService: _FakeComposerService(),
      decoderService: _FakeDecoderService(),
      privateSessionStore: _FakePrivateSessionStore(),
      keyVerificationService: _FakeKeyVerificationService(
        const ConversationKeyTrust(
          isAvailable: true,
          isVerified: false,
          hasKeyChanged: true,
          fingerprint: 'dead beef',
          peerUser: AppUser(
            id: 2,
            username: 'bob',
            displayName: 'Bob',
            devices: [],
          ),
        ),
      ),
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
  Future<ChatMessage> sendMessage(int conversationId, String body) async {
    return ChatMessage(
      id: 1,
      conversationId: conversationId,
      senderId: 1,
      senderName: 'Alice',
      body: body,
      createdAt: DateTime.parse('2026-07-04T00:00:00Z'),
    );
  }
}

class _FakeComposerService implements MessageComposerService {
  @override
  Future<String> compose({
    required int currentUserId,
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    return plaintext;
  }
}

class _FakeDecoderService implements MessageDecoderService {
  @override
  Future<String> decode({
    required int currentUserId,
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    return payload;
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

class _FakePrivateSessionStore extends PrivateSessionStore {
  _FakePrivateSessionStore() : super();
}
