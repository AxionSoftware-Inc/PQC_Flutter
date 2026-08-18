part of 'auth_repository.dart';

// ignore_for_file: unused_element

mixin _AuthSessionActions on _AuthRepositoryBase {
  Future<void> _resetLocalStateIfServerChanged();
  Future<void> _reconcileLocalHistoryOwner(SessionUser session);
  Future<void> syncCurrentDevice();
  Future<void> logout({
    bool clearRememberedIdentity = false,
    bool preserveLocalHistory = true,
  });

  Future<String> suggestedBootstrapName() async {
    final rememberedIdentity = await sessionStorage.readRememberedIdentity();
    if (rememberedIdentity != null &&
        rememberedIdentity.displayName.trim().isNotEmpty) {
      return rememberedIdentity.displayName.trim();
    }

    final deviceIdentity =
        (await deviceStateManager.resolveCurrentDeviceProfile()).deviceIdentity;
    return deviceIdentity.deviceName.trim();
  }

  Future<SessionUser> updateProfile(
    SessionUser current, {
    required String displayName,
    List<int>? avatarBytes,
    String avatarFilename = '',
  }) async {
    var response = await apiClient.patch('/users/me', {
      'display_name': displayName,
    });
    if (avatarBytes != null && avatarBytes.isNotEmpty) {
      response = await apiClient.multipartPost(
        '/users/me/avatar',
        files: [
          http.MultipartFile.fromBytes(
            'avatar',
            avatarBytes,
            filename: avatarFilename.isEmpty ? 'avatar.jpg' : avatarFilename,
            contentType: _avatarMediaType(avatarFilename),
          ),
        ],
      );
    }
    if (response is! Map<String, dynamic>) {
      throw ApiException(
        'Profil javobi noto‘g‘ri formatda.',
        code: 'profile_response_invalid',
      );
    }
    final updated = current.copyWith(
      username: response['username'] as String? ?? current.username,
      displayName: response['display_name'] as String? ?? displayName,
      avatarUrl: response['avatar_url'] as String? ?? current.avatarUrl,
    );
    await sessionStorage.write(updated);
    return updated;
  }

  MediaType _avatarMediaType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) {
      return MediaType('image', 'png');
    }
    if (lower.endsWith('.webp')) {
      return MediaType('image', 'webp');
    }
    return MediaType('image', 'jpeg');
  }

  Future<SessionUser> bootstrapLogin() async {
    final bootstrapName = await suggestedBootstrapName();
    return login(bootstrapName);
  }

  Future<SessionUser?> restoreSession() async {
    await _resetLocalStateIfServerChanged();
    final session = await sessionStorage.read();
    apiClient.setToken(session?.token);
    apiClient.setRecoveryGrant(null);
    apiClient.setRecoveryDeviceCredential(session?.recoveryDeviceCredential);
    final deviceState = await deviceStateManager.resolveCurrentDeviceProfile();
    apiClient.setDeviceId(deviceState.deviceIdentity.id);
    apiClient.setWorkspaceId(
      session == null || session.activeWorkspaceId <= 0
          ? null
          : '${session.activeWorkspaceId}',
    );
    if (session != null) {
      try {
        await syncCurrentDevice();
        final currentDeviceId =
            (await deviceStateManager.resolveCurrentDeviceProfile())
                .deviceIdentity
                .id;
        if (session.deviceId != currentDeviceId) {
          final nextSession = session.copyWith(deviceId: currentDeviceId);
          await sessionStorage.write(nextSession);
          return nextSession;
        }
        return session;
      } catch (_) {
        await logout(clearRememberedIdentity: false);
      }
    }

    // A device name is not an identity. After logout/reinstall, require
    // Google authentication instead of silently creating or selecting a user.
    return null;
  }

  Future<SessionUser> login(String username) async {
    await _resetLocalStateIfServerChanged();
    final deviceState = await _prepareDeviceState();
    final deviceIdentity = deviceState.deviceIdentity;
    final deviceKeyMaterial = deviceState.identityKeyMaterial;
    final pqcSigningKeyMaterial = deviceState.pqcSigningKeyMaterial;
    final pqcPayload = _buildPqcRegistrationPayloadFromState(deviceState);
    apiClient.setDeviceId(deviceIdentity.id);
    final response =
        await apiClient.post('/auth/login', {
              'username': username,
              'display_name': username,
              'device_id': deviceIdentity.id,
              'device_name': deviceIdentity.deviceName,
              'platform': deviceIdentity.platform,
              'identity_public_key': deviceKeyMaterial.publicKey,
              'key_algorithm': deviceKeyMaterial.algorithm,
              'pqc_public_key': pqcPayload.publicKey,
              'pqc_algorithm': pqcPayload.algorithm,
              'pqc_signing_public_key': pqcSigningKeyMaterial.publicKey,
              'pqc_signing_algorithm': pqcSigningKeyMaterial.algorithm,
              'supported_protocols': _supportedProtocolIds(),
            })
            as Map<String, dynamic>;
    _assertServerAcceptedPqcKeys(
      response: response,
      expectedDeviceId: deviceIdentity.id,
      expectedPqcPublicKey: pqcPayload.publicKey,
      expectedSigningPublicKey: pqcSigningKeyMaterial.publicKey,
    );

    final user = response['user'] as Map<String, dynamic>;
    final session = SessionUser(
      id: user['id'] as int,
      accountId:
          response['account_id'] as int? ??
          user['account_id'] as int? ??
          user['id'] as int,
      username: user['username'] as String,
      displayName:
          (user['display_name'] as String?) ?? user['username'] as String,
      avatarUrl: user['avatar_url'] as String? ?? '',
      deviceId: response['device_id'] as String? ?? deviceIdentity.id,
      deviceStatus: response['device_status'] as String? ?? 'active',
      profileFingerprint: response['profile_fingerprint'] as String? ?? '',
      recoveryDeviceCredential:
          response['recovery_device_credential'] as String? ?? '',
      activeWorkspaceId: response['active_workspace_id'] as int? ?? 0,
      organizations: _parseOrganizations(response),
      token: response['token'] as String,
    );

    apiClient.setToken(session.token);
    apiClient.setRecoveryDeviceCredential(session.recoveryDeviceCredential);
    apiClient.setWorkspaceId(
      session.activeWorkspaceId <= 0 ? null : '${session.activeWorkspaceId}',
    );
    await _reconcileLocalHistoryOwner(session);
    await sessionStorage.write(session);
    await sessionStorage.writeApiBaseUrl(ApiConfig.baseUrl);
    await deviceStateManager.markDeviceProfileSynced(
      serverProfileFingerprint: session.profileFingerprint,
      installationStatus: DeviceInstallationStatus.values.firstWhere(
        (item) => item.name == session.deviceStatus,
        orElse: () => DeviceInstallationStatus.active,
      ),
    );
    return session;
  }

  Future<SessionUser?> _tryLoginWithRememberedDevice() async {
    try {
      final deviceState = await _prepareDeviceState();
      final deviceIdentity = deviceState.deviceIdentity;
      final deviceKeyMaterial = deviceState.identityKeyMaterial;
      final pqcSigningKeyMaterial = deviceState.pqcSigningKeyMaterial;
      final pqcPayload = _buildPqcRegistrationPayloadFromState(deviceState);
      apiClient.setDeviceId(deviceIdentity.id);
      final response =
          await apiClient.post('/auth/login', {
                'display_name': deviceIdentity.deviceName,
                'username': '',
                'remember_device_only': true,
                'device_id': deviceIdentity.id,
                'device_name': deviceIdentity.deviceName,
                'platform': deviceIdentity.platform,
                'identity_public_key': deviceKeyMaterial.publicKey,
                'key_algorithm': deviceKeyMaterial.algorithm,
                'pqc_public_key': pqcPayload.publicKey,
                'pqc_algorithm': pqcPayload.algorithm,
                'pqc_signing_public_key': pqcSigningKeyMaterial.publicKey,
                'pqc_signing_algorithm': pqcSigningKeyMaterial.algorithm,
                'supported_protocols': _supportedProtocolIds(),
              })
              as Map<String, dynamic>;
      _assertServerAcceptedPqcKeys(
        response: response,
        expectedDeviceId: deviceIdentity.id,
        expectedPqcPublicKey: pqcPayload.publicKey,
        expectedSigningPublicKey: pqcSigningKeyMaterial.publicKey,
      );
      final user = response['user'] as Map<String, dynamic>;
      final session = SessionUser(
        id: user['id'] as int,
        accountId:
            response['account_id'] as int? ??
            user['account_id'] as int? ??
            user['id'] as int,
        username: user['username'] as String,
        displayName:
            (user['display_name'] as String?) ?? user['username'] as String,
        avatarUrl: user['avatar_url'] as String? ?? '',
        deviceId: response['device_id'] as String? ?? deviceIdentity.id,
        deviceStatus: response['device_status'] as String? ?? 'active',
        profileFingerprint: response['profile_fingerprint'] as String? ?? '',
        recoveryDeviceCredential:
            response['recovery_device_credential'] as String? ?? '',
        activeWorkspaceId: response['active_workspace_id'] as int? ?? 0,
        organizations: _parseOrganizations(response),
        token: response['token'] as String,
      );
      apiClient.setToken(session.token);
      apiClient.setRecoveryDeviceCredential(session.recoveryDeviceCredential);
      apiClient.setWorkspaceId(
        session.activeWorkspaceId <= 0 ? null : '${session.activeWorkspaceId}',
      );
      await _reconcileLocalHistoryOwner(session);
      await sessionStorage.write(session);
      await sessionStorage.writeApiBaseUrl(ApiConfig.baseUrl);
      await deviceStateManager.markDeviceProfileSynced(
        serverProfileFingerprint: session.profileFingerprint,
        installationStatus: DeviceInstallationStatus.values.firstWhere(
          (item) => item.name == session.deviceStatus,
          orElse: () => DeviceInstallationStatus.active,
        ),
      );
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<SessionUser> _sessionFromResponse(
    Map<String, dynamic> response,
    String fallbackDeviceId,
  ) async {
    final user = response['user'] as Map<String, dynamic>;
    final session = SessionUser(
      id: user['id'] as int,
      accountId: response['account_id'] as int? ?? user['id'] as int,
      username: user['username'] as String,
      displayName:
          user['display_name'] as String? ?? user['username'] as String,
      avatarUrl: user['avatar_url'] as String? ?? '',
      deviceId: response['device_id'] as String? ?? fallbackDeviceId,
      deviceStatus: response['device_status'] as String? ?? 'active',
      profileFingerprint: response['profile_fingerprint'] as String? ?? '',
      recoveryDeviceCredential:
          response['recovery_device_credential'] as String? ?? '',
      activeWorkspaceId: response['active_workspace_id'] as int? ?? 0,
      organizations: _parseOrganizations(response),
      token: response['token'] as String,
    );
    apiClient.setToken(session.token);
    apiClient.setDeviceId(session.deviceId);
    apiClient.setRecoveryDeviceCredential(session.recoveryDeviceCredential);
    apiClient.setWorkspaceId(
      session.activeWorkspaceId <= 0 ? null : '${session.activeWorkspaceId}',
    );
    await _reconcileLocalHistoryOwner(session);
    await sessionStorage.write(session);
    await sessionStorage.writeApiBaseUrl(ApiConfig.baseUrl);
    return session;
  }

  Future<SessionUser> switchWorkspace(
    SessionUser session,
    int workspaceId,
  ) async {
    final response =
        await apiClient.post('/users/me/workspace', {
              'workspace_id': workspaceId,
            })
            as Map<String, dynamic>;
    final nextSession = session.copyWith(
      activeWorkspaceId: response['active_workspace_id'] as int? ?? workspaceId,
    );
    apiClient.setWorkspaceId(
      nextSession.activeWorkspaceId <= 0
          ? null
          : '${nextSession.activeWorkspaceId}',
    );
    await sessionStorage.write(nextSession);
    await sessionStorage.writeApiBaseUrl(ApiConfig.baseUrl);
    return nextSession;
  }
}
