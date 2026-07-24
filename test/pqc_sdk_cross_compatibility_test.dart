import 'package:crypto_core/crypto_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_engine_flutter_adapter/pqc_engine_flutter_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final privateConversation = Conversation(
    id: 301,
    type: 'private',
    title: '',
    participantIds: [1, 2],
    lastMessagePreview: '',
    updatedAt: _date,
  );
  final groupConversation = Conversation(
    id: 302,
    type: 'group',
    title: '',
    participantIds: [1, 2],
    lastMessagePreview: '',
    updatedAt: _date,
  );

  late _DeviceFixture alice;
  late _DeviceFixture bob;
  late Map<int, AppUser> users;

  setUp(() async {
    alice = await _DeviceFixture.create('alice-device');
    bob = await _DeviceFixture.create('bob-device');
    users = {
      1: await alice.user(id: 1, username: 'alice'),
      2: await bob.user(id: 2, username: 'bob'),
    };
  });

  test('SDK private writer is readable by frozen V2 on both devices', () async {
    final sdkAlice = alice.sdkPrivate();
    final payload = await sdkAlice.encrypt(
      context: _context(1, privateConversation, users),
      plaintext: 'sdk-to-legacy',
    );

    expect(
      await bob.legacyPrivate().decrypt(
        currentUserId: 2,
        conversation: privateConversation,
        payload: payload,
        usersById: users,
      ),
      'sdk-to-legacy',
    );
    expect(
      await alice.legacyPrivate().decrypt(
        currentUserId: 1,
        conversation: privateConversation,
        payload: payload,
        usersById: users,
      ),
      'sdk-to-legacy',
    );
  });

  test('frozen V2 private writer is readable by SDK on both devices', () async {
    final payload = await alice.legacyPrivate().encrypt(
      currentUserId: 1,
      conversation: privateConversation,
      plaintext: 'legacy-to-sdk',
      usersById: users,
    );

    expect(
      await bob.sdkPrivate().decrypt(
        context: _context(2, privateConversation, users),
        payload: payload,
      ),
      'legacy-to-sdk',
    );
    expect(
      await alice.sdkPrivate().decrypt(
        context: _context(1, privateConversation, users),
        payload: payload,
      ),
      'legacy-to-sdk',
    );
  });

  test('SDK reads pre-reinstall history from recovered keysets', () async {
    final payload = await alice.sdkPrivate().encrypt(
      context: _context(1, privateConversation, users),
      plaintext: 'survives-reinstall',
    );
    final recoveredSnapshots = await bob.registry.readAllKeysets();

    final reinstalledBob = await _DeviceFixture.create('bob-device-new');
    await reinstalledBob.registry.importKeysets(recoveredSnapshots);
    final usersAfterReinstall = {
      1: users[1]!,
      2: (await reinstalledBob.user(id: 2, username: 'bob')).copyWith(
        devices: [
          ...users[2]!.devices.map(
            (device) => device.copyWith(status: 'historical'),
          ),
          ...(await reinstalledBob.user(id: 2, username: 'bob')).devices,
        ],
      ),
    };

    expect(
      await reinstalledBob.sdkPrivate().decrypt(
        context: _context(2, privateConversation, usersAfterReinstall),
        payload: payload,
      ),
      'survives-reinstall',
    );
  });

  test('SDK and frozen V2 group payloads are mutually readable', () async {
    final provider = _FixedGroupKeyProvider();
    final sdkGroup = SdkV2GroupChatAlgorithm(groupKeyStore: provider);
    final legacyGroup = GroupCipherMessageCodec(groupKeyStore: provider);
    final context = _context(1, groupConversation, users);

    final sdkPayload = await sdkGroup.encrypt(
      context: context,
      plaintext: 'sdk-group',
    );
    expect(
      await legacyGroup.decrypt(
        conversation: groupConversation,
        payload: sdkPayload,
        usersById: users,
      ),
      'sdk-group',
    );

    final legacyPayload = await legacyGroup.encrypt(
      conversation: groupConversation,
      plaintext: 'legacy-group',
      usersById: users,
    );
    expect(
      await sdkGroup.decrypt(context: context, payload: legacyPayload),
      'legacy-group',
    );
  });
}

final _date = DateTime.utc(2026, 7, 24);

ChatCryptoContext _context(
  int userId,
  Conversation conversation,
  Map<int, AppUser> users,
) {
  return ChatCryptoContext(
    currentUserId: userId,
    conversation: conversation,
    usersById: users,
  );
}

class _DeviceFixture {
  _DeviceFixture({
    required this.deviceId,
    required this.identity,
    required this.pqc,
    required this.signing,
    required this.registry,
  });

  final String deviceId;
  final _FakeDeviceIdentityService identity;
  final DevicePqcKeyService pqc;
  final DevicePqcSigningKeyService signing;
  final KeyMaterialRegistry registry;

  static Future<_DeviceFixture> create(String deviceId) async {
    final store = _MemorySecretStore();
    final identity = _FakeDeviceIdentityService(deviceId);
    final pqc = DevicePqcKeyService(secretStore: store);
    final signing = DevicePqcSigningKeyService(secretStore: store);
    final registry = KeyMaterialRegistry(
      deviceIdentityService: identity,
      deviceKeyService: DeviceKeyService(secretStore: store),
      devicePqcKeyService: pqc,
      devicePqcSigningKeyService: signing,
      secretStore: store,
    );
    await registry.ensureCurrentKeysetRegistered();
    return _DeviceFixture(
      deviceId: deviceId,
      identity: identity,
      pqc: pqc,
      signing: signing,
      registry: registry,
    );
  }

  Future<AppUser> user({required int id, required String username}) async {
    final pqcMaterial = await pqc.getOrCreateKeyMaterial();
    final signingMaterial = await signing.getOrCreateKeyMaterial();
    return AppUser(
      id: id,
      username: username,
      displayName: username,
      devices: [
        AppUserDevice(
          deviceId: deviceId,
          deviceName: deviceId,
          platform: 'test',
          identityPublicKey: '',
          keyAlgorithm: '',
          pqcPublicKey: pqcMaterial.publicKey,
          pqcAlgorithm: pqcMaterial.algorithm,
          pqcSigningPublicKey: signingMaterial.publicKey,
          pqcSigningAlgorithm: signingMaterial.algorithm,
        ),
      ],
    );
  }

  PqcPrivateMessageCodec legacyPrivate() {
    return PqcPrivateMessageCodec(
      deviceIdentityService: identity,
      devicePqcKeyService: pqc,
      devicePqcSigningKeyService: signing,
      keyMaterialRegistry: registry,
    );
  }

  SdkV2PrivateChatAlgorithm sdkPrivate() {
    return SdkV2PrivateChatAlgorithm(
      deviceIdentityService: identity,
      devicePqcKeyService: pqc,
      devicePqcSigningKeyService: signing,
      keyMaterialRegistry: registry,
    );
  }
}

class _FakeDeviceIdentityService extends DeviceIdentityService {
  _FakeDeviceIdentityService(this.deviceId);

  final String deviceId;

  @override
  Future<DeviceIdentity> getIdentity() async {
    return DeviceIdentity(id: deviceId, deviceName: deviceId, platform: 'test');
  }
}

class _MemorySecretStore extends LocalSecretStore {
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

class _FixedGroupKeyProvider implements GroupKeyProvider {
  final GroupKeyMaterial key = GroupKeyMaterial(
    keyId: 'group-epoch-1',
    secretKeyBytes: List<int>.generate(32, (index) => index),
  );

  @override
  Future<GroupKeyMaterial?> getExistingKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
    String? requestedKeyId,
  }) async {
    return requestedKeyId == null || requestedKeyId == key.keyId ? key : null;
  }

  @override
  Future<GroupKeyMaterial> getOrCreateKey({
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    return key;
  }
}
