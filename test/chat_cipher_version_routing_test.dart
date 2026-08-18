import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _WriterAlgorithm implements ChatCipherAlgorithm, ChatCipherWriter {
  _WriterAlgorithm({
    required this.prefix,
    required this.group,
    this.outputPrefix,
  });

  final String prefix;
  final bool group;
  final String? outputPrefix;

  @override
  bool supportsConversation(Conversation conversation) =>
      conversation.isGroup == group;

  @override
  bool canDecrypt(String payload) => payload.startsWith(prefix);

  @override
  bool canWritePrefix(String requestedPrefix) => requestedPrefix == prefix;

  @override
  Future<String> encrypt({
    required ChatCryptoContext context,
    required String plaintext,
  }) async => '${outputPrefix ?? prefix}$plaintext';

  @override
  Future<String> decrypt({
    required ChatCryptoContext context,
    required String payload,
  }) async => payload.substring(prefix.length);
}

Conversation _conversation({required bool group}) => Conversation(
  id: group ? 2 : 1,
  type: group ? 'group' : 'private',
  title: group ? 'Group' : 'Private',
  participantIds: const [1, 2],
  lastMessagePreview: '',
  updatedAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'V2 and V2.5 route private/group messages through the V2 writer',
    () async {
      for (final profile in [PayloadWriteProfile.v2, PayloadWriteProfile.v25]) {
        final manager = ProtocolVersionManager(
          registry: PayloadFormatRegistry(writeProfile: profile),
        );
        final service = RoutedChatCipherService(
          algorithms: [
            _WriterAlgorithm(prefix: 'pqc:v2:', group: false),
            _WriterAlgorithm(prefix: 'group:v2:', group: true),
            _WriterAlgorithm(prefix: 'pqc:v3:', group: false),
            _WriterAlgorithm(prefix: 'group:v3:', group: true),
          ],
          outboundMessageCache: OutboundMessageCache(),
          protocolVersionManager: manager,
        );

        final privatePayload = await service.encrypt(
          context: ChatCryptoContext(
            currentUserId: 1,
            conversation: _conversation(group: false),
            usersById: const {},
          ),
          plaintext: 'private',
        );
        final groupPayload = await service.encrypt(
          context: ChatCryptoContext(
            currentUserId: 1,
            conversation: _conversation(group: true),
            usersById: const {},
          ),
          plaintext: 'group',
        );

        expect(privatePayload, startsWith('pqc:v2:'));
        expect(groupPayload, startsWith('group:v2:'));
      }
    },
  );

  test('V3 routes both private and group messages to the V3 writer', () async {
    final manager = ProtocolVersionManager(
      registry: PayloadFormatRegistry(writeProfile: PayloadWriteProfile.v3),
    );
    final service = RoutedChatCipherService(
      algorithms: [
        _WriterAlgorithm(prefix: 'pqc:v2:', group: false),
        _WriterAlgorithm(prefix: 'group:v2:', group: true),
        _WriterAlgorithm(prefix: 'pqc:v3:', group: false),
        _WriterAlgorithm(prefix: 'group:v3:', group: true),
      ],
      outboundMessageCache: OutboundMessageCache(),
      protocolVersionManager: manager,
    );

    final privatePayload = await service.encrypt(
      context: ChatCryptoContext(
        currentUserId: 1,
        conversation: _conversation(group: false),
        usersById: const {},
      ),
      plaintext: 'private',
    );
    final groupPayload = await service.encrypt(
      context: ChatCryptoContext(
        currentUserId: 1,
        conversation: _conversation(group: true),
        usersById: const {},
      ),
      plaintext: 'group',
    );

    expect(privatePayload, startsWith('pqc:v3:'));
    expect(groupPayload, startsWith('group:v3:'));
  });

  test('writer output must match the manager-selected protocol prefix', () {
    final manager = ProtocolVersionManager(
      registry: PayloadFormatRegistry(writeProfile: PayloadWriteProfile.v2),
    );
    final service = RoutedChatCipherService(
      algorithms: [
        _WriterAlgorithm(
          prefix: 'pqc:v2:',
          outputPrefix: 'pqc:v3:',
          group: false,
        ),
      ],
      outboundMessageCache: OutboundMessageCache(),
      protocolVersionManager: manager,
    );

    expect(
      () => service.encrypt(
        context: ChatCryptoContext(
          currentUserId: 1,
          conversation: _conversation(group: false),
          usersById: const {},
        ),
        plaintext: 'mismatch',
      ),
      throwsStateError,
    );
  });
}
