import 'organization_context.dart';

class SessionUser {
  const SessionUser({
    required this.id,
    int? accountId,
    required this.username,
    required this.displayName,
    this.deviceId = '',
    this.deviceStatus = 'active',
    this.profileFingerprint = '',
    this.activeWorkspaceId = 0,
    this.organizations = const [],
    required this.token,
  }) : accountId = accountId ?? id;

  final int id;
  final int accountId;
  final String username;
  final String displayName;
  final String deviceId;
  final String deviceStatus;
  final String profileFingerprint;
  final int activeWorkspaceId;
  final List<OrganizationSummary> organizations;
  final String token;

  SessionUser copyWith({
    int? activeWorkspaceId,
    List<OrganizationSummary>? organizations,
    String? deviceId,
    String? deviceStatus,
    String? profileFingerprint,
  }) {
    return SessionUser(
      id: id,
      accountId: accountId,
      username: username,
      displayName: displayName,
      deviceId: deviceId ?? this.deviceId,
      deviceStatus: deviceStatus ?? this.deviceStatus,
      profileFingerprint: profileFingerprint ?? this.profileFingerprint,
      activeWorkspaceId: activeWorkspaceId ?? this.activeWorkspaceId,
      organizations: organizations ?? this.organizations,
      token: token,
    );
  }
}
