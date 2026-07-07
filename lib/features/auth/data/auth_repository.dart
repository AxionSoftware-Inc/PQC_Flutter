import '../../../core/device/device_identity_service.dart';
import '../../../core/device/device_key_service.dart';
import '../../../core/device/device_pqc_key_service.dart';
import '../../../core/device/device_pqc_signing_key_service.dart';
import '../../../core/device/device_prekey_service.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';
import '../../chat/data/outbox_store.dart';
import '../../crypto/outbound_message_cache.dart';

class AuthRepository {
  AuthRepository({
    required this.apiClient,
    required this.sessionStorage,
    required this.deviceIdentityService,
    required this.deviceKeyService,
    required this.devicePqcKeyService,
    required this.devicePqcSigningKeyService,
    required this.devicePreKeyService,
    this._outboundMessageCache,
    this._outboxStore,
  });

  final ApiClient apiClient;
  final SessionStorage sessionStorage;
  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;
  final DevicePqcKeyService devicePqcKeyService;
  final DevicePqcSigningKeyService devicePqcSigningKeyService;
  final DevicePreKeyService devicePreKeyService;
  final OutboundMessageCache? _outboundMessageCache;
  final OutboxStore? _outboxStore;

  Future<SessionUser?> restoreSession() async {
    final session = await sessionStorage.read();
    apiClient.setToken(session?.token);
    if (session != null) {
      try {
        await syncCurrentDevice();
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
      return await login(rememberedIdentity.displayName);
    } catch (_) {
      return null;
    }
  }

  Future<SessionUser> login(String username) async {
    final deviceIdentity = await deviceIdentityService.getIdentity();
    final deviceKeyMaterial = await deviceKeyService.getOrCreateKeyMaterial();
    final pqcSigningKeyMaterial = await devicePqcSigningKeyService
        .getOrCreateKeyMaterial();
    final preKeys = await devicePreKeyService.ensurePreKeys();
    final pqcPayload = await _buildPqcRegistrationPayload();
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
              'prekeys': preKeys,
            })
            as Map<String, dynamic>;

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
      token: response['token'] as String,
    );

    apiClient.setToken(session.token);
    await sessionStorage.write(session);
    return session;
  }

  Future<void> syncCurrentDevice() async {
    final deviceIdentity = await deviceIdentityService.getIdentity();
    final deviceKeyMaterial = await deviceKeyService.getOrCreateKeyMaterial();
    final pqcSigningKeyMaterial = await devicePqcSigningKeyService
        .getOrCreateKeyMaterial();
    final preKeys = await devicePreKeyService.ensurePreKeys();
    final pqcPayload = await _buildPqcRegistrationPayload();
    apiClient.setDeviceId(deviceIdentity.id);
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
      'prekeys': preKeys,
    });
  }

  Future<void> logout({bool clearRememberedIdentity = true}) async {
    apiClient.setToken(null);
    apiClient.setDeviceId(null);
    await sessionStorage.clear(
      clearRememberedIdentity: clearRememberedIdentity,
    );
    await _outboundMessageCache?.clearAll();
    await _outboxStore?.clear();
  }

  Future<_PqcRegistrationPayload> _buildPqcRegistrationPayload() async {
    if (!devicePqcKeyService.isSupportedOnCurrentPlatform) {
      await devicePqcKeyService.clearKeyMaterial();
      return const _PqcRegistrationPayload(publicKey: '', algorithm: '');
    }

    final pqcKeyMaterial = await devicePqcKeyService.getOrCreateKeyMaterial();
    return _PqcRegistrationPayload(
      publicKey: pqcKeyMaterial.publicKey,
      algorithm: pqcKeyMaterial.algorithm,
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
