import 'package:shared_preferences/shared_preferences.dart';

import '../models/session_user.dart';
import 'local_secret_store.dart';

class RememberedIdentity {
  const RememberedIdentity({
    required this.displayName,
    this.username = '',
  });

  final String displayName;
  final String username;
}

class SessionStorage {
  SessionStorage({LocalSecretStore? secretStore})
    : _secretStore = secretStore ?? LocalSecretStore();

  static const _tokenKey = 'session_token';
  static const _idKey = 'session_user_id';
  static const _accountIdKey = 'session_account_id';
  static const _usernameKey = 'session_username';
  static const _displayNameKey = 'session_display_name';
  static const _deviceIdKey = 'session_device_id';
  static const _rememberedDisplayNameKey = 'remembered_display_name';
  final LocalSecretStore _secretStore;

  Future<SessionUser?> read() async {
    final token = await _secretStore.read(_tokenKey);
    final idValue = await _secretStore.read(_idKey);
    final accountIdValue = await _secretStore.read(_accountIdKey);
    final username = await _secretStore.read(_usernameKey);
    final displayName = await _secretStore.read(_displayNameKey);
    final deviceId = await _secretStore.read(_deviceIdKey);
    final id = idValue == null ? null : int.tryParse(idValue);
    final accountId = accountIdValue == null ? null : int.tryParse(accountIdValue);

    if (token == null ||
        id == null ||
        accountId == null ||
        username == null ||
        displayName == null ||
        deviceId == null) {
      return null;
    }

    return SessionUser(
      id: id,
      accountId: accountId,
      username: username,
      displayName: displayName,
      deviceId: deviceId,
      token: token,
    );
  }

  Future<void> write(SessionUser user) async {
    final preferences = await SharedPreferences.getInstance();
    await _secretStore.write(key: _tokenKey, value: user.token);
    await _secretStore.write(key: _idKey, value: user.id.toString());
    await _secretStore.write(key: _accountIdKey, value: user.accountId.toString());
    await _secretStore.write(key: _usernameKey, value: user.username);
    await _secretStore.write(key: _displayNameKey, value: user.displayName);
    await _secretStore.write(key: _deviceIdKey, value: user.deviceId);
    await preferences.setString(_rememberedDisplayNameKey, user.displayName);
  }

  Future<RememberedIdentity?> readRememberedIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    final displayName = preferences.getString(_rememberedDisplayNameKey);

    if (displayName == null) {
      return null;
    }

    return RememberedIdentity(displayName: displayName, username: displayName);
  }

  Future<void> clear({bool clearRememberedIdentity = true}) async {
    final preferences = await SharedPreferences.getInstance();
    await _secretStore.delete(_tokenKey);
    await _secretStore.delete(_idKey);
    await _secretStore.delete(_accountIdKey);
    await _secretStore.delete(_usernameKey);
    await _secretStore.delete(_displayNameKey);
    await _secretStore.delete(_deviceIdKey);
    if (clearRememberedIdentity) {
      await preferences.remove(_rememberedDisplayNameKey);
    }
  }
}
