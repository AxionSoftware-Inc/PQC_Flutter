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
