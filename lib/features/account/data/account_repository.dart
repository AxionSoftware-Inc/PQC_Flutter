import '../../../core/network/api_client.dart';

/// Data boundary for account settings, device management and recovery APIs.
///
/// Chat presentation code depends on this feature contract instead of the
/// shared HTTP client. Endpoint details stay in one place and are easy to
/// replace with a typed implementation later.
class AccountRepository {
  const AccountRepository._(this._apiClient);

  factory AccountRepository({required ApiClient apiClient}) =>
      AccountRepository._(apiClient);

  final ApiClient _apiClient;

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
    bool includeRecoveryCredentials = false,
  }) {
    return _apiClient.get(
      path,
      queryParameters: queryParameters,
      includeRecoveryCredentials: includeRecoveryCredentials,
    );
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool includeRecoveryCredentials = false,
  }) {
    return _apiClient.post(
      path,
      body,
      includeRecoveryCredentials: includeRecoveryCredentials,
    );
  }

  Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    bool includeRecoveryCredentials = false,
  }) {
    return _apiClient.put(
      path,
      body,
      includeRecoveryCredentials: includeRecoveryCredentials,
    );
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) {
    return _apiClient.patch(path, body);
  }
}
