import '../core/network/api_client.dart';
import 'access_control_models.dart';

class AccessControlRepository {
  const AccessControlRepository({required this.apiClient});

  final ApiClient apiClient;

  Future<WorkspaceAccessSnapshot> fetchMyAccess() async {
    final response = await apiClient.get('/rbac/me') as Map<String, dynamic>;
    return WorkspaceAccessSnapshot.fromJson(response);
  }

  Future<List<WorkspaceAccessRole>> fetchRoles() async {
    final response = await apiClient.get('/rbac/roles') as List<dynamic>;
    return response
        .map(
          (item) => WorkspaceAccessRole.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<WorkspaceAccessRole> saveRole({
    int? roleId,
    required String key,
    required String name,
    String description = '',
    bool isActive = true,
    required Set<String> permissions,
  }) async {
    final payload = <String, dynamic>{
      'key': key,
      'name': name,
      'description': description,
      'is_active': isActive,
      'permissions': permissions.toList()..sort(),
    };
    final response = roleId == null
        ? await apiClient.post('/rbac/roles', payload)
        : await apiClient.patch('/rbac/roles/$roleId', payload);
    return WorkspaceAccessRole.fromJson(response as Map<String, dynamic>);
  }

  Future<void> deleteRole(int roleId) async {
    await apiClient.delete('/rbac/roles/$roleId');
  }

  Future<void> assignRole({
    required int workspaceMemberId,
    required int roleId,
  }) async {
    await apiClient.post('/rbac/assignments', {
      'workspace_member_id': workspaceMemberId,
      'role_id': roleId,
    });
  }

  Future<void> removeAssignment(int assignmentId) async {
    await apiClient.delete('/rbac/assignments/$assignmentId');
  }
}
