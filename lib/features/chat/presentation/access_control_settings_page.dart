import 'package:chat_core/chat_core.dart';
import 'package:flutter/material.dart';

import '../../../app/app_localization.dart';
import '../../../app/design_system/app_design_system.dart';
import '../../../core/models/app_user.dart';

class AccessControlSettingsPage extends StatefulWidget {
  const AccessControlSettingsPage({
    super.key,
    required this.apiClient,
    required this.users,
  });

  final ApiClient apiClient;
  final List<AppUser> users;

  @override
  State<AccessControlSettingsPage> createState() =>
      _AccessControlSettingsPageState();
}

class _AccessControlSettingsPageState extends State<AccessControlSettingsPage> {
  late final AccessControlRepository _repository;
  WorkspaceAccessSnapshot? _snapshot;
  AccessControlCatalog? _catalog;
  List<WorkspaceAccessRole> _roles = const [];
  List<WorkspaceAccessRoleAssignment> _assignments = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _canManage => _snapshot?.allows('roles.manage') == true;

  @override
  void initState() {
    super.initState();
    _repository = AccessControlRepository(apiClient: widget.apiClient);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await _repository.fetchMyAccess();
      final results = await Future.wait<dynamic>([
        _repository.fetchCatalog(),
        _repository.fetchRoles(),
        _repository.fetchAssignments(),
      ]);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _catalog = results[0] as AccessControlCatalog;
        _roles = results[1] as List<WorkspaceAccessRole>;
        _assignments = results[2] as List<WorkspaceAccessRoleAssignment>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await operation();
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(context.appSpacing.lg),
          child: AppStatusBanner(
            message: _error!,
            tone: AppStatusTone.danger,
            action: TextButton(
              onPressed: _load,
              child: Text(context.antiQText(uz: 'Qayta urinish', en: 'Retry')),
            ),
          ),
        ),
      );
    }

    final spacing = context.appSpacing;
    final snapshot = _snapshot!;
    return Stack(
      children: [
        ListView(
          padding: EdgeInsets.all(spacing.md),
          children: [
            AppSectionHeader(
              title: context.antiQText(
                uz: 'Rollar va ruxsatlar',
                en: 'Roles & permissions',
              ),
              subtitle: context.antiQText(
                uz: 'Lavozim profilda ko‘rinadi, tizim ruxsati esa shu yerda boshqariladi.',
                en: 'Job titles stay in profiles; system access is managed here.',
              ),
            ),
            SizedBox(height: spacing.sm),
            AppSurfaceCard(
              backgroundColor: context.appColors.primarySoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.antiQText(
                      uz: 'Sizning tizim rolingiz',
                      en: 'Your system role',
                    ),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    _builtInRoleName(snapshot.builtInRole),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  SizedBox(height: spacing.sm),
                  Wrap(
                    spacing: spacing.xs,
                    runSpacing: spacing.xs,
                    children: [
                      AppBadge(
                        label: context.antiQText(
                          uz: '${snapshot.permissions.length} ta ruxsat',
                          en: '${snapshot.permissions.length} permissions',
                        ),
                        tone: AppStatusTone.info,
                      ),
                      if (_canManage)
                        AppBadge(
                          label: context.antiQText(
                            uz: 'Boshqaruvga ruxsat bor',
                            en: 'Management enabled',
                          ),
                          tone: AppStatusTone.success,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.lg),
            AppSectionHeader(
              title: context.antiQText(uz: 'Maxsus rollar', en: 'Custom roles'),
              subtitle: context.antiQText(
                uz: 'Kompaniya ehtiyojiga mos qo‘shimcha ruxsatlar.',
                en: 'Additional access tailored to the company.',
              ),
              trailing: _canManage
                  ? IconButton.filledTonal(
                      tooltip: context.antiQText(
                        uz: 'Rol yaratish',
                        en: 'Create role',
                      ),
                      onPressed: _busy ? null : () => _showRoleEditor(),
                      icon: const Icon(Icons.add_rounded),
                    )
                  : null,
            ),
            SizedBox(height: spacing.sm),
            if (_roles.isEmpty)
              AppSurfaceCard(
                child: AppEmptyState(
                  message: context.antiQText(
                    uz: 'Hozircha maxsus rol yaratilmagan.',
                    en: 'No custom role has been created yet.',
                  ),
                  icon: Icons.admin_panel_settings_outlined,
                ),
              )
            else
              for (final role in _roles)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing.sm),
                  child: _buildRoleCard(role),
                ),
            SizedBox(height: spacing.lg),
            AppSectionHeader(
              title: context.antiQText(
                uz: 'Xodimlarga biriktirish',
                en: 'Member assignments',
              ),
              subtitle: context.antiQText(
                uz: 'Standart rol saqlanadi, maxsus rollar unga qo‘shimcha bo‘ladi.',
                en: 'Custom roles add to the member’s built-in role.',
              ),
            ),
            SizedBox(height: spacing.sm),
            for (final user in widget.users)
              if (user.workspaceMemberId != null)
                Padding(
                  padding: EdgeInsets.only(bottom: spacing.sm),
                  child: _buildMemberCard(user),
                ),
          ],
        ),
        if (_busy)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }

  Widget _buildRoleCard(WorkspaceAccessRole role) {
    final spacing = context.appSpacing;
    return AppSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (role.description.isNotEmpty)
                      Text(
                        role.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.appColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              if (_canManage)
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') _showRoleEditor(role: role);
                    if (value == 'delete') _confirmDeleteRole(role);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        context.antiQText(uz: 'Tahrirlash', en: 'Edit'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        context.antiQText(uz: 'O‘chirish', en: 'Delete'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Wrap(
            spacing: spacing.xs,
            runSpacing: spacing.xs,
            children: [
              for (final permission in role.permissions)
                AppBadge(
                  label: _permissionLabel(permission),
                  tone: AppStatusTone.info,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(AppUser user) {
    final assignments = _assignments
        .where((item) => item.userId == user.id)
        .toList();
    return AppSurfaceCard(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: AppAvatar(
          label: user.displayName,
          imageUrl: user.avatarUrl,
          radius: 22,
        ),
        title: Text(user.displayName),
        subtitle: Wrap(
          spacing: context.appSpacing.xs,
          runSpacing: context.appSpacing.xs,
          children: [
            AppBadge(label: user.roleLabel, tone: AppStatusTone.info),
            for (final assignment in assignments)
              InputChip(
                visualDensity: const VisualDensity(vertical: -4),
                label: Text(assignment.roleName),
                onDeleted: _canManage
                    ? () => _run(
                        () => _repository.removeAssignment(assignment.id),
                      )
                    : null,
              ),
          ],
        ),
        trailing: _canManage && _roles.isNotEmpty
            ? IconButton(
                tooltip: context.antiQText(
                  uz: 'Maxsus rol biriktirish',
                  en: 'Assign custom role',
                ),
                onPressed: _busy ? null : () => _showRoleAssignment(user),
                icon: const Icon(Icons.add_moderator_outlined),
              )
            : null,
      ),
    );
  }

  Future<void> _showRoleAssignment(AppUser user) async {
    final assignedRoleIds = _assignments
        .where((item) => item.userId == user.id)
        .map((item) => item.roleId)
        .toSet();
    final available = _roles
        .where((item) => item.isActive && !assignedRoleIds.contains(item.id))
        .toList();
    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.antiQText(
              uz: 'Biriktirish uchun boshqa faol rol yo‘q.',
              en: 'There is no other active role to assign.',
            ),
          ),
        ),
      );
      return;
    }
    final role = await showModalBottomSheet<WorkspaceAccessRole>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.all(sheetContext.appSpacing.md),
          children: [
            AppSectionHeader(
              title: user.displayName,
              subtitle: context.antiQText(
                uz: 'Biriktiriladigan rolni tanlang.',
                en: 'Choose a role to assign.',
              ),
            ),
            for (final item in available)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text(item.name),
                subtitle: item.description.isEmpty
                    ? null
                    : Text(item.description),
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
          ],
        ),
      ),
    );
    if (role == null || user.workspaceMemberId == null) return;
    await _run(() async {
      await _repository.assignRole(
        workspaceMemberId: user.workspaceMemberId!,
        roleId: role.id,
      );
    });
  }

  Future<void> _showRoleEditor({WorkspaceAccessRole? role}) async {
    final catalog = _catalog;
    if (catalog == null) return;
    final nameController = TextEditingController(text: role?.name ?? '');
    final keyController = TextEditingController(text: role?.key ?? '');
    final descriptionController = TextEditingController(
      text: role?.description ?? '',
    );
    final selected = <String>{...?role?.permissions};
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            role == null
                ? context.antiQText(uz: 'Yangi rol', en: 'New role')
                : context.antiQText(uz: 'Rolni tahrirlash', en: 'Edit role'),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: context.antiQText(
                        uz: 'Rol nomi',
                        en: 'Role name',
                      ),
                    ),
                    onChanged: (value) {
                      if (role == null && keyController.text.isEmpty) {
                        keyController.text = _slug(value);
                      }
                    },
                  ),
                  TextField(
                    controller: keyController,
                    enabled: role == null,
                    decoration: const InputDecoration(
                      labelText: 'Role key',
                      helperText: 'Masalan: security-auditor',
                    ),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: InputDecoration(
                      labelText: context.antiQText(
                        uz: 'Tavsif',
                        en: 'Description',
                      ),
                    ),
                    maxLines: 2,
                  ),
                  SizedBox(height: dialogContext.appSpacing.md),
                  Text(
                    context.antiQText(uz: 'Ruxsatlar', en: 'Permissions'),
                    style: Theme.of(dialogContext).textTheme.titleSmall,
                  ),
                  SizedBox(height: dialogContext.appSpacing.xs),
                  for (final group in _permissionGroups(catalog.permissions))
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(_categoryLabel(group.key)),
                      subtitle: Text(
                        '${group.value.where((item) => selected.contains(item.code)).length}/${group.value.length}',
                      ),
                      children: [
                        for (final permission in group.value)
                          CheckboxListTile(
                            value: selected.contains(permission.code),
                            contentPadding: EdgeInsets.zero,
                            title: Text(permission.label),
                            subtitle: Text(permission.description),
                            onChanged: (checked) {
                              setDialogState(() {
                                if (checked == true) {
                                  selected.add(permission.code);
                                } else {
                                  selected.remove(permission.code);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.antiQText(uz: 'Bekor qilish', en: 'Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty ||
                    keyController.text.trim().isEmpty) {
                  return;
                }
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(context.antiQText(uz: 'Saqlash', en: 'Save')),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _run(() async {
      await _repository.saveRole(
        roleId: role?.id,
        key: keyController.text.trim(),
        name: nameController.text.trim(),
        description: descriptionController.text.trim(),
        isActive: role?.isActive ?? true,
        permissions: selected,
      );
    });
  }

  Future<void> _confirmDeleteRole(WorkspaceAccessRole role) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          context.antiQText(uz: 'Rol o‘chirilsinmi?', en: 'Delete role?'),
        ),
        content: Text(
          context.antiQText(
            uz: '${role.name} va uning barcha biriktirishlari o‘chadi.',
            en: '${role.name} and all of its assignments will be removed.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.antiQText(uz: 'Yo‘q', en: 'No')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.antiQText(uz: 'O‘chirish', en: 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => _repository.deleteRole(role.id));
    }
  }

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
