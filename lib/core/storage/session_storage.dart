import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_user.dart';

class RememberedIdentity {
  const RememberedIdentity({required this.username, required this.displayName});

  final String username;
  final String displayName;
}

class SessionStorage {
  static const _tokenKey = 'session_token';
  static const _idKey = 'session_user_id';
  static const _usernameKey = 'session_username';
  static const _displayNameKey = 'session_display_name';
  static const _rememberedUsernameKey = 'remembered_username';
  static const _rememberedDisplayNameKey = 'remembered_display_name';

  Future<SessionUser?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_tokenKey);
    final id = preferences.getInt(_idKey);
    final username = preferences.getString(_usernameKey);
    final displayName = preferences.getString(_displayNameKey);

    if (token == null ||
        id == null ||
        username == null ||
        displayName == null) {
      return null;
    }

    return SessionUser(
      id: id,
      username: username,
      displayName: displayName,
      token: token,
    );
  }

  Future<void> write(SessionUser user) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, user.token);
    await preferences.setInt(_idKey, user.id);
    await preferences.setString(_usernameKey, user.username);
    await preferences.setString(_displayNameKey, user.displayName);
    await preferences.setString(_rememberedUsernameKey, user.username);
    await preferences.setString(_rememberedDisplayNameKey, user.displayName);
  }

  Future<RememberedIdentity?> readRememberedIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    final username = preferences.getString(_rememberedUsernameKey);
    final displayName = preferences.getString(_rememberedDisplayNameKey);

    if (username == null || displayName == null) {
      return null;
    }

    return RememberedIdentity(username: username, displayName: displayName);
  }

  Future<void> clear({bool clearRememberedIdentity = true}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_idKey);
    await preferences.remove(_usernameKey);
    await preferences.remove(_displayNameKey);
    if (clearRememberedIdentity) {
      await preferences.remove(_rememberedUsernameKey);
      await preferences.remove(_rememberedDisplayNameKey);
    }
  }
}
