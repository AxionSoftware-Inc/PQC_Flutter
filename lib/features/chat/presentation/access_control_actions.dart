part of 'access_control_settings_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AccessControlActions on _AccessControlSettingsPageState {
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
}
