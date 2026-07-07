import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/models/app_user.dart';
import '../../core/models/conversation.dart';

class UserKeyTrust {
  const UserKeyTrust({
    required this.userId,
    required this.hasUsableKey,
    required this.hasUsablePqcKey,
    required this.hasUsableSigningKey,
    required this.isVerified,
    required this.hasKeyChanged,
    required this.fingerprint,
    required this.pqcFingerprint,
    required this.signingFingerprint,
    required this.isPqcVerified,
    required this.isSigningVerified,
    required this.hasPqcKeyChanged,
    required this.hasSigningKeyChanged,
  });

  final int userId;
  final bool hasUsableKey;
  final bool hasUsablePqcKey;
  final bool hasUsableSigningKey;
  final bool isVerified;
  final bool hasKeyChanged;
  final String? fingerprint;
  final String? pqcFingerprint;
  final String? signingFingerprint;
  final bool isPqcVerified;
  final bool isSigningVerified;
  final bool hasPqcKeyChanged;
  final bool hasSigningKeyChanged;

  bool get needsAttention =>
      hasKeyChanged ||
      hasPqcKeyChanged ||
      hasSigningKeyChanged ||
      !hasUsableKey;

  bool get isEnterpriseReady =>
      hasUsableKey && hasUsablePqcKey && hasUsableSigningKey;

  bool get isEnterpriseVerified =>
      isVerified &&
      (!hasUsablePqcKey || isPqcVerified) &&
      (!hasUsableSigningKey || isSigningVerified);

  bool get hasAnyKeyChanged =>
      hasKeyChanged || hasPqcKeyChanged || hasSigningKeyChanged;
}

class ConversationKeyTrust {
  const ConversationKeyTrust({
    required this.isAvailable,
    required this.isEnterpriseReady,
    required this.isVerified,
    required this.isEnterpriseVerified,
    required this.hasKeyChanged,
    required this.hasEnterpriseKeyChanged,
    required this.fingerprint,
    required this.pqcFingerprint,
    required this.signingFingerprint,
    required this.peerUser,
  });

  final bool isAvailable;
  final bool isEnterpriseReady;
  final bool isVerified;
  final bool isEnterpriseVerified;
  final bool hasKeyChanged;
  final bool hasEnterpriseKeyChanged;
  final String? fingerprint;
  final String? pqcFingerprint;
  final String? signingFingerprint;
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
        hasUsablePqcKey: false,
        hasUsableSigningKey: false,
        isVerified: false,
        hasKeyChanged: false,
        fingerprint: null,
        pqcFingerprint: null,
        signingFingerprint: null,
        isPqcVerified: false,
        isSigningVerified: false,
        hasPqcKeyChanged: false,
        hasSigningKeyChanged: false,
      );
    }

    final fingerprint = await _fingerprintForKeyMaterial(
      device.identityPublicKey,
    );
    final pqcFingerprint = device.hasUsableMlKemKey
        ? await _fingerprintForKeyMaterial(device.pqcPublicKey)
        : null;
    final signingFingerprint = device.hasUsableMlDsaKey
        ? await _fingerprintForKeyMaterial(device.pqcSigningPublicKey)
        : null;
    final preferences = await SharedPreferences.getInstance();
    final verifiedFingerprint = preferences.getString(
      _verifiedFingerprintKey(user.id),
    );
    final verifiedPqcFingerprint = preferences.getString(
      _verifiedPqcFingerprintKey(user.id),
    );
    final verifiedSigningFingerprint = preferences.getString(
      _verifiedSigningFingerprintKey(user.id),
    );
    final lastSeenFingerprint = preferences.getString(
      _lastSeenFingerprintKey(user.id),
    );
    final lastSeenPqcFingerprint = preferences.getString(
      _lastSeenPqcFingerprintKey(user.id),
    );
    final lastSeenSigningFingerprint = preferences.getString(
      _lastSeenSigningFingerprintKey(user.id),
    );

    if (lastSeenFingerprint != fingerprint) {
      await preferences.setString(
        _lastSeenFingerprintKey(user.id),
        fingerprint,
      );
    }
    if (pqcFingerprint != null && lastSeenPqcFingerprint != pqcFingerprint) {
      await preferences.setString(
        _lastSeenPqcFingerprintKey(user.id),
        pqcFingerprint,
      );
    }
    if (signingFingerprint != null &&
        lastSeenSigningFingerprint != signingFingerprint) {
      await preferences.setString(
        _lastSeenSigningFingerprintKey(user.id),
        signingFingerprint,
      );
    }

    return UserKeyTrust(
      userId: user.id,
      hasUsableKey: true,
      hasUsablePqcKey: device.hasUsableMlKemKey,
      hasUsableSigningKey: device.hasUsableMlDsaKey,
      isVerified: verifiedFingerprint == fingerprint,
      hasKeyChanged:
          verifiedFingerprint != null && verifiedFingerprint != fingerprint,
      fingerprint: _formatFingerprint(fingerprint),
      pqcFingerprint: pqcFingerprint == null
          ? null
          : _formatFingerprint(pqcFingerprint),
      signingFingerprint: signingFingerprint == null
          ? null
          : _formatFingerprint(signingFingerprint),
      isPqcVerified:
          pqcFingerprint != null && verifiedPqcFingerprint == pqcFingerprint,
      isSigningVerified:
          signingFingerprint != null &&
          verifiedSigningFingerprint == signingFingerprint,
      hasPqcKeyChanged:
          pqcFingerprint != null &&
          verifiedPqcFingerprint != null &&
          verifiedPqcFingerprint != pqcFingerprint,
      hasSigningKeyChanged:
          signingFingerprint != null &&
          verifiedSigningFingerprint != null &&
          verifiedSigningFingerprint != signingFingerprint,
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
        isEnterpriseReady: false,
        isVerified: false,
        isEnterpriseVerified: false,
        hasKeyChanged: false,
        hasEnterpriseKeyChanged: false,
        fingerprint: null,
        pqcFingerprint: null,
        signingFingerprint: null,
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
        isEnterpriseReady: false,
        isVerified: false,
        isEnterpriseVerified: false,
        hasKeyChanged: false,
        hasEnterpriseKeyChanged: false,
        fingerprint: null,
        pqcFingerprint: null,
        signingFingerprint: null,
        peerUser: null,
      );
    }

    final trust = await getUserTrust(peerUser);
    return ConversationKeyTrust(
      isAvailable: trust.hasUsableKey,
      isEnterpriseReady: trust.isEnterpriseReady,
      isVerified: trust.isVerified,
      isEnterpriseVerified: trust.isEnterpriseVerified,
      hasKeyChanged: trust.hasKeyChanged,
      hasEnterpriseKeyChanged: trust.hasAnyKeyChanged,
      fingerprint: trust.fingerprint,
      pqcFingerprint: trust.pqcFingerprint,
      signingFingerprint: trust.signingFingerprint,
      peerUser: peerUser,
    );
  }

  Future<void> verifyUser(AppUser user) async {
    final device = user.preferredX25519Device;
    if (device == null) {
      return;
    }

    final fingerprint = await _fingerprintForKeyMaterial(
      device.identityPublicKey,
    );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_verifiedFingerprintKey(user.id), fingerprint);
    await preferences.setString(_lastSeenFingerprintKey(user.id), fingerprint);
    if (device.hasUsableMlKemKey) {
      final pqcFingerprint = await _fingerprintForKeyMaterial(
        device.pqcPublicKey,
      );
      await preferences.setString(
        _verifiedPqcFingerprintKey(user.id),
        pqcFingerprint,
      );
      await preferences.setString(
        _lastSeenPqcFingerprintKey(user.id),
        pqcFingerprint,
      );
    }
    if (device.hasUsableMlDsaKey) {
      final signingFingerprint = await _fingerprintForKeyMaterial(
        device.pqcSigningPublicKey,
      );
      await preferences.setString(
        _verifiedSigningFingerprintKey(user.id),
        signingFingerprint,
      );
      await preferences.setString(
        _lastSeenSigningFingerprintKey(user.id),
        signingFingerprint,
      );
    }
  }

  Future<String> _fingerprintForKeyMaterial(String keyMaterial) async {
    final digest = await _sha256.hash(base64Decode(keyMaterial));
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

  String _verifiedPqcFingerprintKey(int userId) =>
      '${_verifiedFingerprintPrefix}_pqc_$userId';

  String _lastSeenPqcFingerprintKey(int userId) =>
      '${_lastSeenFingerprintPrefix}_pqc_$userId';

  String _verifiedSigningFingerprintKey(int userId) =>
      '${_verifiedFingerprintPrefix}_signing_$userId';

  String _lastSeenSigningFingerprintKey(int userId) =>
      '${_lastSeenFingerprintPrefix}_signing_$userId';
}
