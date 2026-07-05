import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_user.dart';
import 'local_secret_store.dart';

class RememberedIdentity {
  const RememberedIdentity({required this.username, required this.displayName});

  final String username;
  final String displayName;
}

class SessionStorage {
  SessionStorage({LocalSecretStore? secretStore})
    : _secretStore = secretStore ?? LocalSecretStore();

  static const _tokenKey = 'session_token';
  static const _idKey = 'session_user_id';
  static const _usernameKey = 'session_username';
  static const _displayNameKey = 'session_display_name';
  static const _rememberedUsernameKey = 'remembered_username';
  static const _rememberedDisplayNameKey = 'remembered_display_name';
  final LocalSecretStore _secretStore;

  Future<SessionUser?> read() async {
    final token = await _secretStore.read(_tokenKey);
    final idValue = await _secretStore.read(_idKey);
    final username = await _secretStore.read(_usernameKey);
    final displayName = await _secretStore.read(_displayNameKey);
    final id = idValue == null ? null : int.tryParse(idValue);

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
    await _secretStore.write(key: _tokenKey, value: user.token);
    await _secretStore.write(key: _idKey, value: user.id.toString());
    await _secretStore.write(key: _usernameKey, value: user.username);
    await _secretStore.write(key: _displayNameKey, value: user.displayName);
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
    await _secretStore.delete(_tokenKey);
    await _secretStore.delete(_idKey);
    await _secretStore.delete(_usernameKey);
    await _secretStore.delete(_displayNameKey);
    if (clearRememberedIdentity) {
      await preferences.remove(_rememberedUsernameKey);
      await preferences.remove(_rememberedDisplayNameKey);
    }
  }
}
