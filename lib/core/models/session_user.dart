class SessionUser {
  const SessionUser({
    required this.id,
    int? accountId,
    required this.username,
    required this.displayName,
    this.deviceId = '',
    required this.token,
  }) : accountId = accountId ?? id;

  final int id;
  final int accountId;
  final String username;
  final String displayName;
  final String deviceId;
  final String token;
}
