class AccessPermissionDefinition {
  const AccessPermissionDefinition({
    required this.code,
    required this.label,
    required this.description,
    required this.category,
  });

  factory AccessPermissionDefinition.fromJson(Map<String, dynamic> json) {
    return AccessPermissionDefinition(
      code: json['code'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
    );
  }

  final String code;
  final String label;
  final String description;
  final String category;
}

class BuiltInAccessRole {
  const BuiltInAccessRole({
    required this.key,
    required this.name,
    required this.description,
    required this.permissions,
  });

  factory BuiltInAccessRole.fromJson(Map<String, dynamic> json) {
    return BuiltInAccessRole(
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  final String key;
  final String name;
  final String description;
  final Set<String> permissions;
}

class AccessControlCatalog {
  const AccessControlCatalog({
    required this.workspaceId,
    required this.permissions,
    required this.builtInRoles,
  });

  factory AccessControlCatalog.fromJson(Map<String, dynamic> json) {
    return AccessControlCatalog(
      workspaceId: json['workspace_id'] as int? ?? 0,
      permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
          .map(
            (item) => AccessPermissionDefinition.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false),
      builtInRoles: ((json['built_in_roles'] as List<dynamic>?) ?? const [])
          .map(
            (item) => BuiltInAccessRole.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  final int workspaceId;
  final List<AccessPermissionDefinition> permissions;
  final List<BuiltInAccessRole> builtInRoles;
}

class WorkspaceAccessRole {
  const WorkspaceAccessRole({
    required this.id,
    required this.workspaceId,
    required this.key,
    required this.name,
    required this.description,
    required this.isActive,
    required this.permissions,
  });

  factory WorkspaceAccessRole.fromJson(Map<String, dynamic> json) {
    return WorkspaceAccessRole(
      id: json['id'] as int? ?? 0,
      workspaceId: json['workspace_id'] as int? ?? 0,
      key: json['key'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? false,
      permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  final int id;
  final int workspaceId;
  final String key;
  final String name;
  final String description;
  final bool isActive;
  final Set<String> permissions;
}

class WorkspaceAccessSnapshot {
  const WorkspaceAccessSnapshot({
    required this.workspaceId,
    required this.workspaceMemberId,
    required this.builtInRole,
    required this.customRoles,
    required this.permissions,
  });

  factory WorkspaceAccessSnapshot.fromJson(Map<String, dynamic> json) {
    return WorkspaceAccessSnapshot(
      workspaceId: json['workspace_id'] as int? ?? 0,
      workspaceMemberId: json['workspace_member_id'] as int? ?? 0,
      builtInRole: json['built_in_role'] as String? ?? 'member',
      customRoles: ((json['custom_roles'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toSet(),
      permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  final int workspaceId;
  final int workspaceMemberId;
  final String builtInRole;
  final Set<String> customRoles;
  final Set<String> permissions;

  bool allows(String permissionCode) => permissions.contains(permissionCode);
}

class WorkspaceAccessRoleAssignment {
  const WorkspaceAccessRoleAssignment({
    required this.id,
    required this.workspaceMemberId,
    required this.userId,
    required this.roleId,
    required this.roleKey,
    required this.roleName,
  });

  factory WorkspaceAccessRoleAssignment.fromJson(Map<String, dynamic> json) {
    return WorkspaceAccessRoleAssignment(
      id: json['id'] as int? ?? 0,
      workspaceMemberId: json['workspace_member_id'] as int? ?? 0,
      userId: json['user_id'] as int? ?? 0,
      roleId: json['role_id'] as int? ?? 0,
      roleKey: json['role_key'] as String? ?? '',
      roleName: json['role_name'] as String? ?? '',
    );
  }

  final int id;
  final int workspaceMemberId;
  final int userId;
  final int roleId;
  final String roleKey;
  final String roleName;
}
