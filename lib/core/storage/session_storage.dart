import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/organization_context.dart';
import '../models/session_user.dart';
import 'local_secret_store.dart';

class RememberedIdentity {
  const RememberedIdentity({required this.displayName, this.username = ''});

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
  static const _activeWorkspaceIdKey = 'session_active_workspace_id';
  static const _organizationsKey = 'session_organizations';
  static const _apiBaseUrlKey = 'session_api_base_url';
  static const _rememberedDisplayNameKey = 'remembered_display_name';
  final LocalSecretStore _secretStore;

  Future<SessionUser?> read() async {
    final token = await _secretStore.read(_tokenKey);
    final idValue = await _secretStore.read(_idKey);
    final accountIdValue = await _secretStore.read(_accountIdKey);
    final username = await _secretStore.read(_usernameKey);
    final displayName = await _secretStore.read(_displayNameKey);
    final deviceId = await _secretStore.read(_deviceIdKey);
    final activeWorkspaceIdValue = await _secretStore.read(
      _activeWorkspaceIdKey,
    );
    final id = idValue == null ? null : int.tryParse(idValue);
    final accountId = accountIdValue == null
        ? null
        : int.tryParse(accountIdValue);
    final activeWorkspaceId = activeWorkspaceIdValue == null
        ? 0
        : int.tryParse(activeWorkspaceIdValue) ?? 0;
    final preferences = await SharedPreferences.getInstance();
    final organizations =
        (preferences.getStringList(_organizationsKey) ?? const <String>[])
            .map((item) => OrganizationSummary.fromJson(jsonDecode(item)))
            .toList();

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
      activeWorkspaceId: activeWorkspaceId,
      organizations: organizations,
      token: token,
    );
  }

  Future<void> write(SessionUser user) async {
    final preferences = await SharedPreferences.getInstance();
    await _secretStore.write(key: _tokenKey, value: user.token);
    await _secretStore.write(key: _idKey, value: user.id.toString());
    await _secretStore.write(
      key: _accountIdKey,
      value: user.accountId.toString(),
    );
    await _secretStore.write(key: _usernameKey, value: user.username);
    await _secretStore.write(key: _displayNameKey, value: user.displayName);
    await _secretStore.write(key: _deviceIdKey, value: user.deviceId);
    await _secretStore.write(
      key: _activeWorkspaceIdKey,
      value: user.activeWorkspaceId.toString(),
    );
    await preferences.setStringList(
      _organizationsKey,
      user.organizations
          .map(
            (item) => jsonEncode({
              'id': item.id,
              'name': item.name,
              'slug': item.slug,
              'brand_color': item.brandColor,
              'brand_logo_url': item.brandLogoUrl,
              'current_role': item.currentRole,
              'workspaces': item.workspaces
                  .map(
                    (workspace) => {
                      'id': workspace.id,
                      'organization_id': workspace.organizationId,
                      'name': workspace.name,
                      'slug': workspace.slug,
                      'policy_flags': workspace.policyFlags,
                      'is_default': workspace.isDefault,
                    },
                  )
                  .toList(),
            }),
          )
          .toList(),
    );
    await preferences.setString(_rememberedDisplayNameKey, user.displayName);
  }

  Future<String?> readApiBaseUrl() async {
    return _secretStore.read(_apiBaseUrlKey);
  }

  Future<void> writeApiBaseUrl(String value) async {
    await _secretStore.write(key: _apiBaseUrlKey, value: value);
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
    await _secretStore.delete(_activeWorkspaceIdKey);
    await _secretStore.delete(_apiBaseUrlKey);
    await preferences.remove(_organizationsKey);
    if (clearRememberedIdentity) {
      await preferences.remove(_rememberedDisplayNameKey);
    }
  }
}
