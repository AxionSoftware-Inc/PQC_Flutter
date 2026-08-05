import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/network/api_client.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({
    super.key,
    required this.apiClient,
    this.standalone = true,
  });

  final ApiClient apiClient;
  final bool standalone;

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  final TextEditingController _memberSearchController = TextEditingController();
  bool _loading = true;
  bool _isAdmin = false;
  String? _error;
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _members = const [];
  String _memberStatusFilter = 'active';
  int? _memberRoleFilter;

  @override
  void initState() {
    super.initState();
    _memberSearchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _memberSearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredMembers {
    final query = _memberSearchController.text.trim().toLowerCase();
    return _members.where((member) {
      final isActive = member['is_active'] == true;
      if (_memberStatusFilter == 'active' && !isActive) return false;
      if (_memberStatusFilter == 'inactive' && isActive) return false;
      final role = member['role'] as Map<String, dynamic>?;
      if (_memberRoleFilter != null && role?['id'] != _memberRoleFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        member['display_name'],
        member['email'],
        role?['name'],
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.apiClient.get('/rbac/me'),
        widget.apiClient.get('/rbac/roles'),
        widget.apiClient.get('/rbac/members'),
      ]);
      if (!mounted) return;
      setState(() {
        _isAdmin = (results[0] as Map<String, dynamic>)['is_admin'] == true;
        _roles = List<Map<String, dynamic>>.from(results[1] as List);
        _members = List<Map<String, dynamic>>.from(results[2] as List);
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

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: AppStatusBanner(
          message: _error!,
          tone: AppStatusTone.danger,
          action: TextButton(
            onPressed: _load,
            child: const Text('Qayta urinish'),
          ),
        ),
      );
    }
    if (!_isAdmin) {
      return const Center(
        child: AppEmptyState(
          message: 'Bu bo‘lim faqat administratorlar uchun.',
          icon: Icons.admin_panel_settings_outlined,
        ),
      );
    }
    final spacing = context.appSpacing;
    final activeMembers = _members
        .where((member) => member['is_active'] == true)
        .length;
    final inactiveMembers = _members.length - activeMembers;
    final filteredMembers = _filteredMembers;
    final content = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(spacing.md),
        children: [
          AppSurfaceCard(
            backgroundColor: context.appColors.primarySoft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.admin_panel_settings_rounded),
                  title: Text('Xodimlar va lavozimlar'),
                  subtitle: Text(
                    'Lavozim, ko‘rish doirasi va ish holatini shu yerda boshqaring.',
                  ),
                ),
                Wrap(
                  spacing: spacing.sm,
                  runSpacing: spacing.sm,
                  children: [
                    _statChip(Icons.groups_rounded, '$activeMembers faol'),
                    _statChip(Icons.badge_outlined, '${_roles.length} lavozim'),
                    if (inactiveMembers > 0)
                      _statChip(
                        Icons.person_off_outlined,
                        '$inactiveMembers ishdan olingan',
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.lg),
          AppSectionHeader(
            title: 'Lavozimlar',
            subtitle: '1 — eng yuqori daraja.',
            trailing: Wrap(
              spacing: spacing.xs,
              children: [
                if (_roles.isEmpty)
                  TextButton.icon(
                    onPressed: _bootstrapDefaultRoles,
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Standart'),
                  ),
                IconButton.filledTonal(
                  onPressed: _editRole,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          SizedBox(height: spacing.xs),
          if (_roles.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 720;
                if (!isWide) {
                  return Column(
                    children: [
                      for (final role in _roles)
                        Padding(
                          padding: EdgeInsets.only(bottom: spacing.xs),
                          child: _roleTile(role),
                        ),
                    ],
                  );
                }
                final columns = constraints.maxWidth >= 1200 ? 4 : 2;
                final cardWidth =
                    (constraints.maxWidth - spacing.sm * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: spacing.sm,
                  runSpacing: spacing.sm,
                  children: [
                    for (final role in _roles)
                      SizedBox(width: cardWidth, child: _roleTile(role)),
                  ],
                );
              },
            ),
          if (_roles.isEmpty)
            const AppEmptyState(
              message: 'Lavozim yarating: Direktor, Menejer, Xodim.',
              icon: Icons.badge_outlined,
            ),
          SizedBox(height: spacing.lg),
          AppSectionHeader(
            title: 'Xodimlar',
            subtitle: '${filteredMembers.length} / ${_members.length} xodim',
          ),
          SizedBox(height: spacing.xs),
          AppSurfaceCard(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.sm,
              vertical: spacing.xs,
            ),
            child: TextField(
              controller: _memberSearchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Ism, email yoki lavozim bo‘yicha qidirish',
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(height: spacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _memberFilterChip('Faol', 'active'),
                SizedBox(width: spacing.xs),
                _memberFilterChip('Ishdan olingan', 'inactive'),
                SizedBox(width: spacing.xs),
                _memberFilterChip('Barchasi', 'all'),
                for (final role in _roles) ...[
                  SizedBox(width: spacing.xs),
                  FilterChip(
                    label: Text(role['name'] as String? ?? ''),
                    selected: _memberRoleFilter == role['id'],
                    onSelected: (selected) => setState(
                      () => _memberRoleFilter = selected
                          ? role['id'] as int
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: spacing.sm),
          if (filteredMembers.isEmpty)
            const AppEmptyState(
              message: 'Bu qidiruv bo‘yicha xodim topilmadi.',
              icon: Icons.person_search_outlined,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final count = width >= 1120
                    ? 4
                    : width >= 720
                    ? 3
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredMembers.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisSpacing: spacing.sm,
                    crossAxisSpacing: spacing.sm,
                    childAspectRatio: count == 1 ? 5.4 : 2.8,
                  ),
                  itemBuilder: (context, index) =>
                      _memberTile(filteredMembers[index]),
                );
              },
            ),
        ],
      ),
    );
    final addEmployeeButton = FloatingActionButton.extended(
      onPressed: _invite,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: const Text('Xodim qo‘shish'),
    );
    if (!widget.standalone) {
      return Stack(
        children: [
          content,
          Positioned(right: 16, bottom: 16, child: addEmployeeButton),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: addEmployeeButton,
      body: content,
    );
  }

  Widget _roleTile(Map<String, dynamic> role) => Card(
    child: ListTile(
      leading: CircleAvatar(child: Text('${role['rank']}')),
      title: Text(role['name'] as String? ?? ''),
      subtitle: Text(
        _visibilityLabel(role['visibility'] as String? ?? 'lower'),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'edit') _editRole(role: role);
          if (value == 'delete') _deleteRole(role);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Tahrirlash')),
          PopupMenuItem(value: 'delete', child: Text('O‘chirish')),
        ],
      ),
    ),
  );

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

  Widget _memberFilterChip(String label, String value) => FilterChip(
    label: Text(label),
    selected: _memberStatusFilter == value,
    onSelected: (_) => setState(() => _memberStatusFilter = value),
  );

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

  Widget _statChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 16), const SizedBox(width: 6), Text(label)],
    ),
  );

  String _visibilityLabel(String value) => switch (value) {
    'all' => 'Barcha xodimlar ko‘rinadi',
    'self' => 'Faqat o‘zi ko‘rinadi',
    _ => 'O‘zi va past lavozimdagilar ko‘rinadi',
  };

  Future<void> _invite() async {
    final email = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yangi xodimni taklif qilish'),
        content: TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email manzil'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, email.text.trim()),
            child: const Text('Taklif yuborish'),
          ),
        ],
      ),
    );
    if (value?.isEmpty != false) return;
    try {
      final invitation = await widget.apiClient.post('/rbac/invitations', {
        'email': value,
      });
      await _load();
      if (!mounted) return;
      final code = invitation['invite_code'] as String? ?? '';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Taklif tayyor'),
          content: code.isEmpty
              ? Text('$value manziliga taklif yaratildi.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value uchun taklif kodi:'),
                    const SizedBox(height: 12),
                    SelectableText(
                      code,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text('Kodini xodimga yuboring.'),
                  ],
                ),
          actions: [
            if (code.isNotEmpty)
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Taklif kodi nusxalandi.')),
                    );
                  }
                },
                child: const Text('Nusxalash'),
              ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tayyor'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _editRole({Map<String, dynamic>? role}) async {
    final name = TextEditingController(text: role?['name'] as String? ?? '');
    final rank = TextEditingController(
      text: '${role?['rank'] ?? _roles.length + 1}',
    );
    var visibility = role?['visibility'] as String? ?? 'lower';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(role == null ? 'Yangi lavozim' : 'Lavozimni tahrirlash'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Lavozim nomi'),
              ),
              TextField(
                controller: rank,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Daraja'),
              ),
              DropdownButtonFormField(
                initialValue: visibility,
                items: const [
                  DropdownMenuItem(
                    value: 'all',
                    child: Text('Hamma ko‘rinadi'),
                  ),
                  DropdownMenuItem(
                    value: 'lower',
                    child: Text('Pastlar ko‘rinadi'),
                  ),
                  DropdownMenuItem(value: 'self', child: Text('Faqat o‘zi')),
                ],
                onChanged: (value) => update(() => visibility = value!),
                decoration: const InputDecoration(labelText: 'Ko‘rish qoidasi'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Saqlash'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _run(() async {
      final body = {
        'name': name.text.trim(),
        'rank': int.tryParse(rank.text) ?? 99,
        'visibility': visibility,
      };
      if (role == null) {
        await widget.apiClient.post('/rbac/roles', body);
      } else {
        await widget.apiClient.patch('/rbac/roles/${role['id']}', body);
      }
    });
  }

  Future<void> _bootstrapDefaultRoles() async {
    await _run(() async {
      await widget.apiClient.post('/rbac/roles/bootstrap-defaults', {});
    });
  }

  Future<void> _assignRole(Map<String, dynamic> member) async {
    final roleId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Lavozim tanlang')),
          ListTile(
            leading: const Icon(Icons.remove_circle_outline_rounded),
            title: const Text('Lavozimni olib tashlash'),
            onTap: () => Navigator.pop(context, -1),
          ),
          ..._roles.map(
            (item) => ListTile(
              title: Text(item['name'] as String),
              subtitle: Text(_visibilityLabel(item['visibility'] as String)),
              onTap: () => Navigator.pop(context, item['id'] as int),
            ),
          ),
        ],
      ),
    );
    if (roleId == null) return;
    await _run(() async {
      await widget.apiClient.put('/rbac/members/${member['member_id']}/role', {
        'role_id': roleId < 0 ? null : roleId,
      });
    });
  }

  Future<void> _deleteRole(Map<String, dynamic> role) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lavozim o‘chirilsinmi?'),
        content: Text(
          '${role['name']} lavozimi o‘chiriladi. Biriktirilgan xodimlar lavozimsiz qoladi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('O‘chirish'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _run(() async {
        await widget.apiClient.delete('/rbac/roles/${role['id']}');
      });
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
        await widget.apiClient.post(
          '/rbac/members/${member['member_id']}/deactivate',
          {},
        );
      });
    }
  }

  Future<void> _reactivate(Map<String, dynamic> member) async {
    await _run(() async {
      await widget.apiClient.post(
        '/rbac/members/${member['member_id']}/reactivate',
        {},
      );
    });
  }
}
