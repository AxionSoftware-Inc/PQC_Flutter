part of 'auth_repository.dart';

// ignore_for_file: unused_element

mixin _AuthDeviceActions on _AuthRepositoryBase {
  Future<void> syncCurrentDevice() async {
    final deviceState = await _prepareDeviceState();
    final deviceIdentity = deviceState.deviceIdentity;
    final deviceKeyMaterial = deviceState.identityKeyMaterial;
    final pqcSigningKeyMaterial = deviceState.pqcSigningKeyMaterial;
    final pqcPayload = _buildPqcRegistrationPayloadFromState(deviceState);
    apiClient.setDeviceId(deviceIdentity.id);
    final response =
        await apiClient.post('/users/me/device', {
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
    await deviceStateManager.markDeviceProfileSynced(
      serverProfileFingerprint:
          response['profile_fingerprint'] as String? ?? '',
      installationStatus: DeviceInstallationStatus.values.firstWhere(
        (item) =>
            item.name == (response['device_status'] as String? ?? 'active'),
        orElse: () => DeviceInstallationStatus.active,
      ),
    );
  }

  Future<void> logout({
    bool clearRememberedIdentity = false,
    bool preserveLocalHistory = true,
  }) async {
    apiClient.setToken(null);
    apiClient.setDeviceId(null);
    apiClient.setWorkspaceId(null);
    apiClient.setRecoveryGrant(null);
    apiClient.setRecoveryDeviceCredential(null);
    await sessionStorage.clear(
      clearRememberedIdentity: clearRememberedIdentity,
    );
    if (!preserveLocalHistory) {
      await appDatabase?.clearAllChatData();
      await _outboundMessageCache?.clearAll();
      await _outboxStore?.clear();
      await sessionStorage.clearLocalHistoryOwner();
    }
  }

  Future<void> _resetLocalStateIfServerChanged() async {
    final storedApiBaseUrl = await sessionStorage.readApiBaseUrl();
    if (storedApiBaseUrl == ApiConfig.baseUrl) {
      return;
    }
    await appDatabase?.clearAllChatData();
    await _outboundMessageCache?.clearAll();
    await _outboxStore?.clear();
    if (storedApiBaseUrl != null && storedApiBaseUrl.isNotEmpty) {
      await sessionStorage.clear(clearRememberedIdentity: false);
      await sessionStorage.clearLocalHistoryOwner();
    }
    await sessionStorage.writeApiBaseUrl(ApiConfig.baseUrl);
  }

  Future<void> _reconcileLocalHistoryOwner(SessionUser session) async {
    final currentOwner = await sessionStorage.readLocalHistoryOwner();
    if (currentOwner == null) {
      await sessionStorage.writeLocalHistoryOwner(session);
      return;
    }
    final matchesCurrentIdentity =
        currentOwner.accountId == session.accountId &&
        currentOwner.username == session.username;
    if (!matchesCurrentIdentity) {
      await appDatabase?.clearAllChatData();
      await _outboundMessageCache?.clearAll();
      await _outboxStore?.clear();
    }
    await sessionStorage.writeLocalHistoryOwner(session);
  }
}
