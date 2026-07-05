import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/features/security/key_verification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('user key can be verified and later key change is detected', () async {
    SharedPreferences.setMockInitialValues({});
    final service = KeyVerificationService();
    const firstUser = AppUser(
      id: 2,
      username: 'bob',
      displayName: 'Bob',
      devices: [
        AppUserDevice(
          deviceId: 'bob-device',
          deviceName: 'Bob Phone',
          platform: 'android',
          identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
          keyAlgorithm: 'x25519',
          preKeys: [],
        ),
      ],
    );
    const rotatedUser = AppUser(
      id: 2,
      username: 'bob',
      displayName: 'Bob',
      devices: [
        AppUserDevice(
          deviceId: 'bob-device',
          deviceName: 'Bob Phone',
          platform: 'android',
          identityPublicKey: 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE=',
          keyAlgorithm: 'x25519',
          preKeys: [],
        ),
      ],
    );

    await service.verifyUser(firstUser);

    final verifiedTrust = await service.getUserTrust(firstUser);
    final rotatedTrust = await service.getUserTrust(rotatedUser);

    expect(verifiedTrust.isVerified, isTrue);
    expect(verifiedTrust.hasKeyChanged, isFalse);
    expect(rotatedTrust.isVerified, isFalse);
    expect(rotatedTrust.hasKeyChanged, isTrue);
  });

  test('private conversation trust uses peer verification state', () async {
    SharedPreferences.setMockInitialValues({});
    final service = KeyVerificationService();
    final conversation = Conversation(
      id: 1,
      type: 'private',
      title: '',
      participantIds: const [1, 2],
      lastMessagePreview: '',
      updatedAt: DateTime.parse('2026-07-04T00:00:00Z'),
    );
    const usersById = {
      1: AppUser(id: 1, username: 'alice', displayName: 'Alice', devices: []),
      2: AppUser(
        id: 2,
        username: 'bob',
        displayName: 'Bob',
        devices: [
          AppUserDevice(
            deviceId: 'bob-device',
            deviceName: 'Bob Phone',
            platform: 'android',
            identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
            keyAlgorithm: 'x25519',
            preKeys: [],
          ),
        ],
      ),
    };

    final trust = await service.getConversationTrust(
      currentUserId: 1,
      conversation: conversation,
      usersById: usersById,
    );

    expect(trust.isAvailable, isTrue);
    expect(trust.peerUser?.id, 2);
    expect(trust.isVerified, isFalse);
    expect(trust.fingerprint, isNotNull);
  });
}
