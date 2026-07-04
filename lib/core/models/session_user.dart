class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.token,
  });

  final int id;
  final String username;
  final String displayName;
  final String token;
}
