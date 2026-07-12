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

class LocalHistoryOwner {
  const LocalHistoryOwner({
    required this.accountId,
    required this.username,
    required this.displayName,
  });

  final int accountId;
  final String username;
  final String displayName;
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
  static const _deviceStatusKey = 'session_device_status';
  static const _profileFingerprintKey = 'session_profile_fingerprint';
  static const _activeWorkspaceIdKey = 'session_active_workspace_id';
  static const _organizationsKey = 'session_organizations';
  static const _apiBaseUrlKey = 'session_api_base_url';
  static const _rememberedDisplayNameKey = 'remembered_display_name';
  static const _rememberedUsernameKey = 'remembered_username';
  static const _historyOwnerAccountIdKey = 'history_owner_account_id';
  static const _historyOwnerUsernameKey = 'history_owner_username';
  static const _historyOwnerDisplayNameKey = 'history_owner_display_name';
  final LocalSecretStore _secretStore;

  Future<SessionUser?> read() async {
    final token = await _secretStore.read(_tokenKey);
    final idValue = await _secretStore.read(_idKey);
    final accountIdValue = await _secretStore.read(_accountIdKey);
    final username = await _secretStore.read(_usernameKey);
    final displayName = await _secretStore.read(_displayNameKey);
    final deviceId = await _secretStore.read(_deviceIdKey);
    final deviceStatus = await _secretStore.read(_deviceStatusKey);
    final profileFingerprint = await _secretStore.read(_profileFingerprintKey);
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
      deviceStatus: deviceStatus ?? 'active',
      profileFingerprint: profileFingerprint ?? '',
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
    await _secretStore.write(key: _deviceStatusKey, value: user.deviceStatus);
    await _secretStore.write(
      key: _profileFingerprintKey,
      value: user.profileFingerprint,
    );
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
    await _secretStore.write(
      key: _rememberedDisplayNameKey,
      value: user.displayName,
    );
    await _secretStore.write(key: _rememberedUsernameKey, value: user.username);
    await preferences.remove(_rememberedDisplayNameKey);
    await preferences.remove(_rememberedUsernameKey);
  }

  Future<String?> readApiBaseUrl() async {
    return _secretStore.read(_apiBaseUrlKey);
  }

  Future<void> writeApiBaseUrl(String value) async {
    await _secretStore.write(key: _apiBaseUrlKey, value: value);
  }

  Future<RememberedIdentity?> readRememberedIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    final displayName =
        await _secretStore.read(_rememberedDisplayNameKey) ??
        preferences.getString(_rememberedDisplayNameKey);

    if (displayName == null) {
      return null;
    }

    final username =
        await _secretStore.read(_rememberedUsernameKey) ??
        preferences.getString(_rememberedUsernameKey) ??
        displayName;

    if (preferences.getString(_rememberedDisplayNameKey) != null) {
      await _secretStore.write(
        key: _rememberedDisplayNameKey,
        value: displayName,
      );
      await preferences.remove(_rememberedDisplayNameKey);
    }
    if (preferences.getString(_rememberedUsernameKey) != null) {
      await _secretStore.write(key: _rememberedUsernameKey, value: username);
      await preferences.remove(_rememberedUsernameKey);
    }

    return RememberedIdentity(
      displayName: displayName,
      username: username,
    );
  }

  Future<LocalHistoryOwner?> readLocalHistoryOwner() async {
    final preferences = await SharedPreferences.getInstance();
    final accountIdValue = preferences.getString(_historyOwnerAccountIdKey);
    final username = preferences.getString(_historyOwnerUsernameKey);
    final displayName = preferences.getString(_historyOwnerDisplayNameKey);
    final accountId = accountIdValue == null ? null : int.tryParse(accountIdValue);
    if (accountId == null || username == null || displayName == null) {
      return null;
    }
    return LocalHistoryOwner(
      accountId: accountId,
      username: username,
      displayName: displayName,
    );
  }

  Future<void> writeLocalHistoryOwner(SessionUser user) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _historyOwnerAccountIdKey,
      user.accountId.toString(),
    );
    await preferences.setString(_historyOwnerUsernameKey, user.username);
    await preferences.setString(_historyOwnerDisplayNameKey, user.displayName);
  }

  Future<void> clearLocalHistoryOwner() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_historyOwnerAccountIdKey);
    await preferences.remove(_historyOwnerUsernameKey);
    await preferences.remove(_historyOwnerDisplayNameKey);
  }

  Future<void> clear({bool clearRememberedIdentity = true}) async {
    final preferences = await SharedPreferences.getInstance();
    await _secretStore.delete(_tokenKey);
    await _secretStore.delete(_idKey);
    await _secretStore.delete(_accountIdKey);
    await _secretStore.delete(_usernameKey);
    await _secretStore.delete(_displayNameKey);
    await _secretStore.delete(_deviceIdKey);
    await _secretStore.delete(_deviceStatusKey);
    await _secretStore.delete(_profileFingerprintKey);
    await _secretStore.delete(_activeWorkspaceIdKey);
    await _secretStore.delete(_apiBaseUrlKey);
    await preferences.remove(_organizationsKey);
    if (clearRememberedIdentity) {
      await _secretStore.delete(_rememberedDisplayNameKey);
      await _secretStore.delete(_rememberedUsernameKey);
      await preferences.remove(_rememberedDisplayNameKey);
      await preferences.remove(_rememberedUsernameKey);
    }
  }
}
