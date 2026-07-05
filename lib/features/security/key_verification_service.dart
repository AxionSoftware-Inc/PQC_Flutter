import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';

class UserKeyTrust {
  const UserKeyTrust({
    required this.userId,
    required this.hasUsableKey,
    required this.isVerified,
    required this.hasKeyChanged,
    required this.fingerprint,
  });

  final int userId;
  final bool hasUsableKey;
  final bool isVerified;
  final bool hasKeyChanged;
  final String? fingerprint;

  bool get needsAttention => hasKeyChanged || !hasUsableKey;
}

class ConversationKeyTrust {
  const ConversationKeyTrust({
    required this.isAvailable,
    required this.isVerified,
    required this.hasKeyChanged,
    required this.fingerprint,
    required this.peerUser,
  });

  final bool isAvailable;
  final bool isVerified;
  final bool hasKeyChanged;
  final String? fingerprint;
  final AppUser? peerUser;
}

class KeyVerificationService {
  static const _verifiedFingerprintPrefix = 'verified_fingerprint_user';
  static const _lastSeenFingerprintPrefix = 'last_seen_fingerprint_user';

  final Sha256 _sha256 = Sha256();

  Future<Map<int, UserKeyTrust>> buildUserTrustMap(
    Iterable<AppUser> users,
  ) async {
    final result = <int, UserKeyTrust>{};
    for (final user in users) {
      result[user.id] = await getUserTrust(user);
    }
    return result;
  }

  Future<UserKeyTrust> getUserTrust(AppUser user) async {
    final device = user.preferredX25519Device;
    if (device == null) {
      return UserKeyTrust(
        userId: user.id,
        hasUsableKey: false,
        isVerified: false,
        hasKeyChanged: false,
        fingerprint: null,
      );
    }

    final fingerprint = await _fingerprintForPublicKey(
      device.identityPublicKey,
    );
    final preferences = await SharedPreferences.getInstance();
    final verifiedFingerprint = preferences.getString(
      _verifiedFingerprintKey(user.id),
    );
    final lastSeenFingerprint = preferences.getString(
      _lastSeenFingerprintKey(user.id),
    );

    if (lastSeenFingerprint != fingerprint) {
      await preferences.setString(
        _lastSeenFingerprintKey(user.id),
        fingerprint,
      );
    }

    return UserKeyTrust(
      userId: user.id,
      hasUsableKey: true,
      isVerified: verifiedFingerprint == fingerprint,
      hasKeyChanged:
          verifiedFingerprint != null && verifiedFingerprint != fingerprint,
      fingerprint: _formatFingerprint(fingerprint),
    );
  }

  Future<ConversationKeyTrust> getConversationTrust({
    required int currentUserId,
    required Conversation conversation,
    required Map<int, AppUser> usersById,
  }) async {
    if (conversation.isGroup) {
      return const ConversationKeyTrust(
        isAvailable: false,
        isVerified: false,
        hasKeyChanged: false,
        fingerprint: null,
        peerUser: null,
      );
    }

    final peerUserId = conversation.participantIds.firstWhere(
      (id) => id != currentUserId,
      orElse: () => -1,
    );
    final peerUser = usersById[peerUserId];
    if (peerUser == null) {
      return const ConversationKeyTrust(
        isAvailable: false,
        isVerified: false,
        hasKeyChanged: false,
        fingerprint: null,
        peerUser: null,
      );
    }

    final trust = await getUserTrust(peerUser);
    return ConversationKeyTrust(
      isAvailable: trust.hasUsableKey,
      isVerified: trust.isVerified,
      hasKeyChanged: trust.hasKeyChanged,
      fingerprint: trust.fingerprint,
      peerUser: peerUser,
    );
  }

  Future<void> verifyUser(AppUser user) async {
    final device = user.preferredX25519Device;
    if (device == null) {
      return;
    }

    final fingerprint = await _fingerprintForPublicKey(
      device.identityPublicKey,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_verifiedFingerprintKey(user.id), fingerprint);
    await preferences.setString(_lastSeenFingerprintKey(user.id), fingerprint);
  }

  Future<String> _fingerprintForPublicKey(String publicKey) async {
    final digest = await _sha256.hash(base64Decode(publicKey));
    return digest.bytes
        .take(12)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _formatFingerprint(String fingerprint) {
    final groups = <String>[];
    for (var index = 0; index < fingerprint.length; index += 4) {
      final end = (index + 4 < fingerprint.length)
          ? index + 4
          : fingerprint.length;
      groups.add(fingerprint.substring(index, end));
    }
    return groups.join(' ');
  }

  String _verifiedFingerprintKey(int userId) =>
      '${_verifiedFingerprintPrefix}_$userId';

  String _lastSeenFingerprintKey(int userId) =>
      '${_lastSeenFingerprintPrefix}_$userId';
}
