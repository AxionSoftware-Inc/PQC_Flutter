part of 'admin_panel_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _AdminPanelMemberMutations on _AdminPanelPageState {

  Widget _memberTile(Map<String, dynamic> member) {
    final role = member['role'] as Map<String, dynamic>?;
    final isActive = member['is_active'] == true;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showMemberDetails(member),
        child: ListTile(
          leading: AppAvatar(label: member['display_name'] as String? ?? ''),
          title: Text(member['display_name'] as String? ?? ''),
          subtitle: Text(
            isActive
                ? (role?['name'] as String? ?? 'Lavozim berilmagan')
                : 'Ishdan olingan',
            style: isActive ? null : TextStyle(color: context.appColors.danger),
          ),
          trailing: Icon(
            isActive ? Icons.chevron_right_rounded : Icons.person_off_outlined,
            color: isActive
                ? context.appColors.textMuted
                : context.appColors.danger,
          ),
        ),
      ),
    );
  }

  Future<void> _showMemberDetails(Map<String, dynamic> member) async {
    final role = member['role'] as Map<String, dynamic>?;
    final isActive = member['is_active'] == true;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final spacing = sheetContext.appSpacing;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              spacing.lg,
              spacing.xs,
              spacing.lg,
              spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppAvatar(
                      label: member['display_name'] as String? ?? '',
                      radius: 28,
                    ),
                    SizedBox(width: spacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member['display_name'] as String? ?? '',
                            style: Theme.of(sheetContext).textTheme.titleMedium,
                          ),
                          if ((member['email'] as String? ?? '').isNotEmpty)
                            Text(
                              member['email'] as String,
                              style: Theme.of(sheetContext).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: spacing.lg),
                AppSurfaceCard(
                  child: Column(
                    children: [
                      _detailRow(
                        'Lavozim',
                        role?['name'] as String? ?? 'Biriktirilmagan',
                      ),
                      _detailRow(
                        'Holat',
                        isActive ? 'Faol xodim' : 'Ishdan olingan',
                      ),
                      _detailRow(
                        'Tizim roli',
                        member['system_role'] as String? ?? 'member',
                      ),
                    ],
                  ),
                ),
                SizedBox(height: spacing.md),
                if (isActive) ...[
                  SizedBox(
                    width: double.infinity,
                    child: AppPrimaryButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _assignRole(member);
                      },
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('Lavozimni o‘zgartirish'),
                    ),
                  ),
                  SizedBox(height: spacing.sm),
                  SizedBox(
                    width: double.infinity,
                    child: AppSecondaryButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _deactivate(member);
                      },
                      label: const Text('Ishdan olish'),
                    ),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: AppPrimaryButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _reactivate(member);
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Qayta ishga olish'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(width: 96, child: Text(label)),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );

  String _visibilityLabel(String value) => switch (value) {
    'all' => 'Barcha xodimlar ko‘rinadi',
    'self' => 'Faqat o‘zi ko‘rinadi',
    _ => 'O‘zi va past lavozimdagilar ko‘rinadi',
  };

  Future<void> _addRegisteredUser() async {
    try {
      final users = List<Map<String, dynamic>>.from(
        await widget.repository.get('/rbac/registered-users') as List,
      );
      if (!mounted) return;
      if (users.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yangi ro‘yxatdan o‘tgan foydalanuvchi topilmadi.'),
          ),
        );
        return;
      }
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              const Text(
                'Yangi ro‘yxatdan o‘tganlar',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ...users.map(
                (user) => ListTile(
                  leading: AppAvatar(
                    label: user['display_name'] as String? ?? 'U',
                    imageUrl: user['avatar_url'] as String?,
                    radius: 21,
                  ),
                  title: Text(
                    user['display_name'] as String? ?? 'Foydalanuvchi',
                  ),
                  subtitle: Text(user['email'] as String? ?? ''),
                  onTap: () => Navigator.pop(sheetContext, user),
                ),
              ),
            ],
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final roleId = await showDialog<int?>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: Text('${selected['display_name']} uchun lavozim'),
          children: [
            for (final role in _roles)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.pop(dialogContext, role['id'] as int),
                child: Text(role['name'] as String? ?? ''),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keyinroq belgilayman'),
            ),
          ],
        ),
      );
      await _run(() async {
        await widget.repository.post('/rbac/members/add', {
          'user_id': selected['user_id'],
          ...?roleId == null ? null : {'role_id': roleId},
        });
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }


  Future<void> _deactivate(Map<String, dynamic> member) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xodim ishdan olinsinmi?'),
        content: Text('${member['display_name']} workspace’dan chiqariladi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ishdan olish'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _run(() async {
        await widget.repository.post(
          '/rbac/members/${member['member_id']}/deactivate',
          {},
        );
      });
    }
  }

  Future<void> _reactivate(Map<String, dynamic> member) async {
    await _run(() async {
      await widget.repository.post(
        '/rbac/members/${member['member_id']}/reactivate',
        {},
      );
    });
  }

}
