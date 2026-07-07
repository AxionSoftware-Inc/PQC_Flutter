import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'package:pqc_chat_app/core/models/conversation.dart';
import 'package:pqc_chat_app/features/security/key_verification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _validMlKem768PublicKey = base64Encode(List<int>.filled(1184, 0));
final _validMlDsa65PublicKey = base64Encode(List<int>.filled(1952, 0));

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

  test(
    'enterprise trust tracks pqc kem and signing verification together',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = KeyVerificationService();
      final user = AppUser(
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
            pqcPublicKey: _validMlKem768PublicKey,
            pqcAlgorithm: 'ml-kem-768',
            pqcSigningPublicKey: _validMlDsa65PublicKey,
            pqcSigningAlgorithm: 'ml-dsa-65',
            preKeys: const [],
          ),
        ],
      );

      final beforeVerify = await service.getUserTrust(user);
      expect(beforeVerify.isEnterpriseReady, isTrue);
      expect(beforeVerify.isEnterpriseVerified, isFalse);

      await service.verifyUser(user);

      final afterVerify = await service.getUserTrust(user);
      expect(afterVerify.isVerified, isTrue);
      expect(afterVerify.isPqcVerified, isTrue);
      expect(afterVerify.isSigningVerified, isTrue);
      expect(afterVerify.isEnterpriseVerified, isTrue);
    },
  );
}
