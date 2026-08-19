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

}
