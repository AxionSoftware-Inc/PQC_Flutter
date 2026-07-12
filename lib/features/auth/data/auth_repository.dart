import '../../../core/device/device_identity_service.dart';
import '../../../core/config/api_config.dart';
import '../../../core/database/app_database.dart';
import '../../../core/device/device_state_manager.dart';
import '../../../core/device/device_key_service.dart';
import '../../../core/device/device_pqc_key_service.dart';
import '../../../core/device/device_pqc_signing_key_service.dart';
import '../../../core/device/device_security_state_service.dart';
import '../../../core/models/organization_context.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../chat/data/outbox_store.dart';
import '../../../core/models/chat_message.dart';
import '../../crypto/outbound_message_cache.dart';

class AuthRepository {
  static const _unsupportedPqcServerMessage =
      'Connected server is running an old backend and does not store PQC device keys yet. Update/deploy the latest backend or switch API_BASE_URL to the updated server.';

  AuthRepository({
    required this.apiClient,
    required this.sessionStorage,
    required this.deviceIdentityService,
    required this.deviceKeyService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    required this.deviceSecurityStateService,
    required this.deviceStateManager,
    this.appDatabase,
    this._outboundMessageCache,
    this._outboxStore,
  });

  final ApiClient apiClient;
  final SessionStorage sessionStorage;
  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final DeviceSecurityStateService deviceSecurityStateService;
  final DeviceStateManager deviceStateManager;
  final AppDatabase? appDatabase;
  final OutboundMessageCache? _outboundMessageCache;
  final OutboxStore? _outboxStore;

  Future<String> suggestedBootstrapName() async {
    final rememberedIdentity = await sessionStorage.readRememberedIdentity();
    if (rememberedIdentity != null &&
        rememberedIdentity.displayName.trim().isNotEmpty) {
      return rememberedIdentity.displayName.trim();
    }

    final deviceIdentity =
        (await deviceStateManager.resolveCurrentDeviceProfile()).deviceIdentity;
    final suffix = deviceIdentity.id.replaceAll('-', '').substring(0, 6);
    final platform = deviceIdentity.platform.toUpperCase();
    return '$platform-$suffix';
  }

  Future<SessionUser> bootstrapLogin() async {
    final bootstrapName = await suggestedBootstrapName();
    return login(bootstrapName);
  }

  Future<SessionUser?> restoreSession() async {
    await _resetLocalStateIfServerChanged();
    final session = await sessionStorage.read();
    apiClient.setToken(session?.token);
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

    final rememberedIdentity = await sessionStorage.readRememberedIdentity();
    if (rememberedIdentity == null) {
      return null;
    }

    try {
      return await login(
        rememberedIdentity.username.isEmpty
            ? rememberedIdentity.displayName
            : rememberedIdentity.username,
      );
    } catch (_) {
      return null;
    }
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
      deviceId: response['device_id'] as String? ?? deviceIdentity.id,
      deviceStatus: response['device_status'] as String? ?? 'active',
      profileFingerprint: response['profile_fingerprint'] as String? ?? '',
      activeWorkspaceId: response['active_workspace_id'] as int? ?? 0,
      organizations: _parseOrganizations(response),
      token: response['token'] as String,
    );

    apiClient.setToken(session.token);
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
            })
            as Map<String, dynamic>;
    _assertServerAcceptedPqcKeys(
      response: response,
      expectedDeviceId: deviceIdentity.id,
      expectedPqcPublicKey: pqcPayload.publicKey,
      expectedSigningPublicKey: pqcSigningKeyMaterial.publicKey,
    );
    await deviceStateManager.markDeviceProfileSynced(
      serverProfileFingerprint: response['profile_fingerprint'] as String? ?? '',
      installationStatus: DeviceInstallationStatus.values.firstWhere(
        (item) => item.name == (response['device_status'] as String? ?? 'active'),
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

  _PqcRegistrationPayload _buildPqcRegistrationPayloadFromState(
    DeviceProfileState deviceState,
  ) {
    final pqcKeyMaterial = deviceState.pqcKeyMaterial;
    if (pqcKeyMaterial == null) {
      return const _PqcRegistrationPayload(publicKey: '', algorithm: '');
    }
    return _PqcRegistrationPayload(
      publicKey: pqcKeyMaterial.publicKey,
      algorithm: pqcKeyMaterial.algorithm,
    );
  }

  Future<DeviceProfileState> _prepareDeviceState() async {
    final deviceState = await deviceStateManager.resolveCurrentDeviceProfile();
    if (deviceState.didRotateInstallation) {
      await _outboundMessageCache?.clearAll();
      final queuedMessages = await _outboxStore?.readAll() ?? const [];
      for (final item in queuedMessages) {
        await _outboxStore?.upsert(
          item.copyWith(
            deliveryState: MessageDeliveryState.failedPermanent,
            failureReason: 'outbox_payload_invalid_after_rotation',
          ),
        );
      }
    }
    return deviceState;
  }

  List<OrganizationSummary> _parseOrganizations(Map<String, dynamic> response) {
    return (response['organizations'] as List<dynamic>? ?? const [])
        .map(
          (item) => OrganizationSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  void _assertServerAcceptedPqcKeys({
    required Map<String, dynamic> response,
    required String expectedDeviceId,
    required String expectedPqcPublicKey,
    required String expectedSigningPublicKey,
  }) {
    if (expectedPqcPublicKey.isEmpty || expectedSigningPublicKey.isEmpty) {
      return;
    }

    final user = response['user'] as Map<String, dynamic>?;
    if (user != null) {
      final devices = user['devices'] as List<dynamic>? ?? const [];
      for (final item in devices) {
        final device = item as Map<String, dynamic>;
        if ((device['device_id'] as String? ?? '') != expectedDeviceId) {
          continue;
        }
        final returnedPqcPublicKey = device['pqc_public_key'] as String? ?? '';
        final returnedSigningPublicKey =
            device['pqc_signing_public_key'] as String? ?? '';
        if (returnedPqcPublicKey == expectedPqcPublicKey &&
            returnedSigningPublicKey == expectedSigningPublicKey) {
          return;
        }
        throw ApiException(
          _unsupportedPqcServerMessage,
          code: 'server_missing_pqc_device_keys',
        );
      }
    }

    final returnedPqcPublicKey = response['pqc_public_key'] as String? ?? '';
    final returnedSigningPublicKey =
        response['pqc_signing_public_key'] as String? ?? '';
    if (returnedPqcPublicKey == expectedPqcPublicKey &&
        returnedSigningPublicKey == expectedSigningPublicKey) {
      return;
    }

    throw ApiException(
      _unsupportedPqcServerMessage,
      code: 'server_missing_pqc_device_keys',
    );
  }
}

class _PqcRegistrationPayload {
  const _PqcRegistrationPayload({
    required this.publicKey,
    required this.algorithm,
  });

  final String publicKey;
  final String algorithm;
}
