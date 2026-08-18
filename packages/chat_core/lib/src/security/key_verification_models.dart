import 'package:crypto_core/crypto_core.dart';

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
