part of 'access_control_settings_page.dart';

extension _AccessControlViews on _AccessControlSettingsPageState {
  Widget _buildView(BuildContext context) {
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
}
