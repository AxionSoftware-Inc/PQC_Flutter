import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/database/app_database.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/chat_message.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/core/storage/local_data_protector.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
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
  test('private send is blocked when verified peer key changed', () async {
    final database = AppDatabase.inMemory();
    final remote = _FakeChatRemoteDataSource();
    final localDataProtector = LocalDataProtector(
      secretStore: _MemorySecretStore(),
    );
    final keyVerificationService = _FakeKeyVerificationService(
      const ConversationKeyTrust(
        isAvailable: true,
        isEnterpriseReady: true,
        isVerified: true,
        isEnterpriseVerified: true,
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
      database: database,
    );
    final repository = ChatRepository(
      remoteDataSource: remote,
      cipherService: _FakeChatCipherService(),
      keyVerificationService: keyVerificationService,
      privateConversationSecurityCoordinator:
          PrivateConversationSecurityCoordinator(
            keyVerificationService: keyVerificationService,
          ),
      database: database,
      localDataProtector: localDataProtector,
      outboxStore: OutboxStore(
        database: database,
        localDataProtector: localDataProtector,
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
    await database.close();
  });

  test(
    'send delegates payload handling to the routed cipher service',
    () async {
      final database = AppDatabase.inMemory();
      final remote = _FakeChatRemoteDataSource();
      final cipherService = _FakeChatCipherService();
      final localDataProtector = LocalDataProtector(
        secretStore: _MemorySecretStore(),
      );
      final repository = ChatRepository(
        remoteDataSource: remote,
        cipherService: cipherService,
        keyVerificationService: _FakeKeyVerificationService(
          const ConversationKeyTrust(
            isAvailable: true,
            isEnterpriseReady: true,
            isVerified: true,
            isEnterpriseVerified: true,
            hasKeyChanged: false,
            hasEnterpriseKeyChanged: false,
            fingerprint: 'dead beef',
            pqcFingerprint: 'bead feed',
            signingFingerprint: 'cafe babe',
            peerUser: AppUser(
              id: 2,
              username: 'bob',
              displayName: 'Bob',
              devices: [],
            ),
          ),
          database: database,
        ),
        privateConversationSecurityCoordinator:
            _NoopPrivateConversationSecurityCoordinator(database: database),
        database: database,
        localDataProtector: localDataProtector,
        outboxStore: OutboxStore(
          database: database,
          localDataProtector: localDataProtector,
        ),
      );

      await repository.fetchUsers();

      final sent = await repository.sendMessage(
        _privateConversation,
        currentUserId: 1,
        text: 'hello',
      );

      expect(cipherService.lastEncryptedPlaintext, 'hello');
      expect(cipherService.lastDecryptPayload, isNull);
      expect(sent.body, 'hello');
      final rows = await database.readMessagesForConversation(_privateConversation.id);
      expect(rows.single.plaintextBody, isNot('hello'));
      await database.close();
    },
  );

  test(
    'private send refreshes users when peer pqc device metadata was stale',
    () async {
      final database = AppDatabase.inMemory();
      final remote = _RefreshingUsersChatRemoteDataSource();
      final cipherService = _PqcAwareChatCipherService();
      final localDataProtector = LocalDataProtector(
        secretStore: _MemorySecretStore(),
      );
      final repository = ChatRepository(
        remoteDataSource: remote,
        cipherService: cipherService,
        keyVerificationService: _FakeKeyVerificationService(
          const ConversationKeyTrust(
            isAvailable: true,
            isEnterpriseReady: true,
            isVerified: false,
            isEnterpriseVerified: false,
            hasKeyChanged: false,
            hasEnterpriseKeyChanged: false,
            fingerprint: 'dead beef',
            pqcFingerprint: 'bead feed',
            signingFingerprint: 'cafe babe',
            peerUser: AppUser(
              id: 2,
              username: 'bob',
              displayName: 'Bob',
              devices: [],
            ),
          ),
          database: database,
        ),
        privateConversationSecurityCoordinator:
            _NoopPrivateConversationSecurityCoordinator(database: database),
        database: database,
        localDataProtector: localDataProtector,
        outboxStore: OutboxStore(
          database: database,
          localDataProtector: localDataProtector,
        ),
      );

      await repository.fetchUsers();

      final sent = await repository.sendMessage(
        _privateConversation,
        currentUserId: 1,
        text: 'hello pqc',
      );

      expect(remote.fetchUsersCallCount, 2);
      expect(cipherService.encryptAttempts, 1);
      expect(sent.body, 'hello pqc');
      await database.close();
    },
  );
}

class _MemorySecretStore extends LocalSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

const _users = [
  AppUser(id: 1, username: 'alice', displayName: 'Alice', devices: []),
  AppUser(id: 2, username: 'bob', displayName: 'Bob', devices: []),
];

final _validMlKem768PublicKey = base64Encode(List<int>.filled(1184, 7));
final _validMlDsa65PublicKey = base64Encode(List<int>.filled(1952, 9));

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
  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    List<int> attachmentIds = const [],
    String clientMessageId = '',
    String messageType = 'text',
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

class _PqcAwareChatCipherService implements ChatCipherService {
  int encryptAttempts = 0;

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async {
    return 'decoded::$payload';
  }

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async {
    encryptAttempts += 1;
    final peerUser = context.usersById[2];
    if (peerUser?.preferredPqcDevice == null) {
      throw ChatEncryptionException(
        'Peer PQC device key is not ready yet. Ask them to reopen the app.',
      );
    }
    return 'cipher::$plaintext';
  }
}

class _FakeKeyVerificationService extends KeyVerificationService {
  _FakeKeyVerificationService(this.trust, {required super.database});

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
  _NoopPrivateConversationSecurityCoordinator({required AppDatabase database})
    : super(
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
          database: database,
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

class _RefreshingUsersChatRemoteDataSource extends ChatRemoteDataSource {
  _RefreshingUsersChatRemoteDataSource() : super(apiClient: ApiClient());

  int fetchUsersCallCount = 0;

  @override
  Future<List<AppUser>> fetchUsers() async {
    fetchUsersCallCount += 1;
    if (fetchUsersCallCount == 1) {
      return _users;
    }
    return [
      _users.first,
      AppUser(
        id: 2,
        username: 'bob',
        displayName: 'Bob',
        devices: [
          AppUserDevice(
            deviceId: 'bob-device',
            deviceName: 'Bob Phone',
            platform: 'android',
            identityPublicKey: '',
            keyAlgorithm: '',
            pqcPublicKey: _validMlKem768PublicKey,
            pqcAlgorithm: 'ml-kem-768',
            pqcSigningPublicKey: _validMlDsa65PublicKey,
            pqcSigningAlgorithm: 'ml-dsa-65',
          ),
        ],
      ),
    ];
  }

  @override
  Future<ChatMessage> sendMessage(
    int conversationId,
    String body, {
    List<int> attachmentIds = const [],
    String clientMessageId = '',
    String messageType = 'text',
  }) async {
    return ChatMessage(
      id: 2,
      conversationId: conversationId,
      senderId: 1,
      senderName: 'Alice',
      body: body,
      createdAt: DateTime.parse('2026-07-04T00:00:00Z'),
      clientMessageId: clientMessageId,
    );
  }
}
