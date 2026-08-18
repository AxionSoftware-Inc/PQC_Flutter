part of 'access_control_settings_page.dart';

extension _AccessControlHelpers on _AccessControlSettingsPageState {
  String _permissionLabel(String code) {
    for (final item in _catalog?.permissions ?? const []) {
      if (item.code == code) return item.label;
    }
    return code;
  }

  String _builtInRoleName(String key) {
    for (final item in _catalog?.builtInRoles ?? const []) {
      if (item.key == key) return item.name;
    }
    return key;
  }

  List<MapEntry<String, List<AccessPermissionDefinition>>> _permissionGroups(
    List<AccessPermissionDefinition> permissions,
  ) {
    final groups = <String, List<AccessPermissionDefinition>>{};
    for (final permission in permissions) {
      groups.putIfAbsent(permission.category, () => []).add(permission);
    }
    return groups.entries.toList();
  }

  String _categoryLabel(String category) => switch (category) {
    'workspace' => context.antiQText(uz: 'Ish maydoni', en: 'Workspace'),
    'members' => context.antiQText(uz: 'Xodimlar', en: 'Members'),
    'roles' => context.antiQText(uz: 'Rollar', en: 'Roles'),
    'security' => context.antiQText(uz: 'Xavfsizlik', en: 'Security'),
    'messaging' => context.antiQText(uz: 'Xabarlar', en: 'Messaging'),
    'audit' => context.antiQText(uz: 'Audit', en: 'Audit'),
    _ => category,
  };

  String _slug(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }
}
