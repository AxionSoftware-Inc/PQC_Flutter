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

  Future<dynamic> getCurrentAccess() => _apiClient.get('/rbac/me');

  Future<dynamic> listRoles() => _apiClient.get('/rbac/roles');

  Future<dynamic> listMembers() => _apiClient.get('/rbac/members');

  Future<dynamic> listRegisteredUsers() =>
      _apiClient.get('/rbac/registered-users');

  Future<dynamic> createRole(Map<String, dynamic> body) =>
      _apiClient.post('/rbac/roles', body);

  Future<dynamic> updateRole(int roleId, Map<String, dynamic> body) =>
      _apiClient.patch('/rbac/roles/$roleId', body);

  Future<dynamic> bootstrapDefaultRoles() =>
      _apiClient.post('/rbac/roles/bootstrap-defaults', const {});

  Future<dynamic> assignRole(int memberId, {required int? roleId}) =>
      _apiClient.put('/rbac/members/$memberId/role', {'role_id': roleId});

  Future<dynamic> deleteRole(int roleId) =>
      _apiClient.delete('/rbac/roles/$roleId');

  Future<dynamic> addMember(int userId, {int? roleId}) =>
      _apiClient.post('/rbac/members/add', {
        'user_id': userId,
        ...?roleId == null ? null : {'role_id': roleId},
      });

  Future<dynamic> deactivateMember(int memberId) =>
      _apiClient.post('/rbac/members/$memberId/deactivate', const {});

  Future<dynamic> reactivateMember(int memberId) =>
      _apiClient.post('/rbac/members/$memberId/reactivate', const {});
}
