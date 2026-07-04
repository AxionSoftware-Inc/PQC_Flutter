import '../../../core/device/device_identity_service.dart';
import '../../../core/device/device_key_service.dart';
import '../../../core/models/session_user.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/session_storage.dart';

class AuthRepository {
  AuthRepository({
    required this.apiClient,
    required this.sessionStorage,
    required this.deviceIdentityService,
    required this.deviceKeyService,
  });

  final ApiClient apiClient;
  final SessionStorage sessionStorage;
  final DeviceIdentityService deviceIdentityService;
  final DeviceKeyService deviceKeyService;

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
    apiClient.setDeviceId(deviceIdentity.id);
    final response =
        await apiClient.post('/auth/login', {
              'username': username,
              'device_id': deviceIdentity.id,
              'device_name': deviceIdentity.deviceName,
              'platform': deviceIdentity.platform,
              'identity_public_key': deviceKeyMaterial.publicKey,
              'key_algorithm': deviceKeyMaterial.algorithm,
            })
            as Map<String, dynamic>;

    final user = response['user'] as Map<String, dynamic>;
    final session = SessionUser(
      id: user['id'] as int,
      username: user['username'] as String,
      displayName:
          (user['display_name'] as String?) ?? user['username'] as String,
      token: response['token'] as String,
    );

    apiClient.setToken(session.token);
    await sessionStorage.write(session);
    return session;
  }

  Future<void> syncCurrentDevice() async {
    final deviceIdentity = await deviceIdentityService.getIdentity();
    final deviceKeyMaterial = await deviceKeyService.getOrCreateKeyMaterial();
    apiClient.setDeviceId(deviceIdentity.id);
    await apiClient.post('/users/me/device', {
      'device_id': deviceIdentity.id,
      'device_name': deviceIdentity.deviceName,
      'platform': deviceIdentity.platform,
      'identity_public_key': deviceKeyMaterial.publicKey,
      'key_algorithm': deviceKeyMaterial.algorithm,
    });
  }

  Future<void> logout({bool clearRememberedIdentity = true}) async {
    apiClient.setToken(null);
    apiClient.setDeviceId(null);
    await sessionStorage.clear(
      clearRememberedIdentity: clearRememberedIdentity,
    );
  }
}
