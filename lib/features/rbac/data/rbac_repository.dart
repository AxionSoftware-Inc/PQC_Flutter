import '../../../core/network/api_client.dart';

/// Feature boundary for RBAC administration.
///
/// Keeping this adapter in data/ prevents widgets from knowing about the
/// shared HTTP client and makes the admin surface easy to replace in tests.
class RbacRepository {
  const RbacRepository._(this._apiClient);

  factory RbacRepository({required ApiClient apiClient}) =>
      RbacRepository._(apiClient);

  final ApiClient _apiClient;

  Future<dynamic> get(String path) => _apiClient.get(path);

  Future<dynamic> post(String path, Map<String, dynamic> body) {
    return _apiClient.post(path, body);
  }

  Future<dynamic> put(String path, Map<String, dynamic> body) {
    return _apiClient.put(path, body);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) {
    return _apiClient.patch(path, body);
  }

  Future<dynamic> delete(String path) => _apiClient.delete(path);
}
