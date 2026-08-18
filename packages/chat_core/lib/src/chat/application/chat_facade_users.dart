part of 'chat_facade.dart';

// ignore_for_file: annotate_overrides

mixin _ChatFacadeUsers on _ChatFacadeBase {
  Future<List<AppUser>> fetchUsers() {
    final inFlight = _usersFetchInFlight;
    if (inFlight != null) {
      return inFlight;
    }
    late final Future<List<AppUser>> operation;
    operation = _fetchUsersOnce();
    _usersFetchInFlight = operation;
    return operation.whenComplete(() {
      if (identical(_usersFetchInFlight, operation)) {
        _usersFetchInFlight = null;
      }
    });
  }

  Future<List<AppUser>> _fetchUsersOnce() async {
    final users = await _remoteDataSource.fetchUsers();
    _usersById
      ..clear()
      ..addEntries(users.map((user) => MapEntry(user.id, user)));
    _lastSecureSendUsersRefreshAt = DateTime.now();
    return users;
  }

  /// Optional RBAC integration. The core chat flow stays independent of this
  /// endpoint; deployments without the RBAC plugin simply never expose the
  /// management action in the UI.
  Future<AppUser> updateUserRole({
    required int userId,
    required String role,
  }) async {
    final user = await _remoteDataSource.updateUserRole(userId, role);
    _usersById[user.id] = user;
    return user;
  }
}
