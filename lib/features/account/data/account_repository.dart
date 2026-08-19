import '../../../core/network/api_client.dart';

/// Data boundary for account settings, device management and recovery APIs.
///
/// Chat application code depends on this feature contract instead of the
/// shared HTTP client. Endpoint details stay in one place and are easy to
/// replace with typed DTOs later.
class AccountRepository {
  const AccountRepository._(this._apiClient);

  factory AccountRepository({required ApiClient apiClient}) =>
      AccountRepository._(apiClient);

  final ApiClient _apiClient;

  Future<dynamic> getAccountSettings() => _apiClient.get('/users/me/settings');

  Future<dynamic> updateAccountSettings(Map<String, dynamic> values) =>
      _apiClient.patch('/users/me/settings', values);

  Future<dynamic> revokeDevice(String deviceId) =>
      _apiClient.post('/users/me/devices/$deviceId/revoke', const {});

  Future<dynamic> saveEncryptedBackup({
    required String encryptedBlob,
    required String blobSha256,
    int version = 1,
  }) => _apiClient.put('/users/me/crypto-backup', {
    'version': version,
    'encrypted_blob': encryptedBlob,
    'blob_sha256': blobSha256,
  });

  Future<dynamic> getEncryptedBackup() =>
      _apiClient.get('/users/me/crypto-backup');

  Future<dynamic> getRecoveryManifest({
    Map<String, String>? queryParameters,
    bool includeRecoveryCredentials = false,
  }) => _apiClient.get(
    '/users/me/crypto-recovery',
    queryParameters: queryParameters,
    includeRecoveryCredentials: includeRecoveryCredentials,
  );

  Future<dynamic> requestRecoveryApproval(String requesterDeviceId) =>
      _apiClient.post('/users/me/crypto-recovery/approvals', {
        'requester_device_id': requesterDeviceId,
      }, includeRecoveryCredentials: true);

  Future<dynamic> listRecoveryApprovals() => _apiClient.get(
    '/users/me/crypto-recovery/approvals',
    includeRecoveryCredentials: true,
  );

  Future<dynamic> decideRecoveryApproval({
    required int approvalId,
    required String approverDeviceId,
    required bool approved,
  }) => _apiClient.post(
    '/users/me/crypto-recovery/approvals/$approvalId',
    {'approver_device_id': approverDeviceId, 'approved': approved},
    includeRecoveryCredentials: true,
  );

  Future<dynamic> saveRecoveryManifest({
    required int schemaVersion,
    required String payload,
    required String sourceDeviceId,
    required int expectedSequence,
  }) => _apiClient.put('/users/me/crypto-recovery', {
    'schema_version': schemaVersion,
    'payload': payload,
    'source_device_id': sourceDeviceId,
    'expected_sequence': expectedSequence,
  }, includeRecoveryCredentials: true);
}
