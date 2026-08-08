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
    final filteredMembers = _filteredMembers;
    final content = RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.all(spacing.md),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberSearchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Xodim yoki lavozimni qidirish',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                tooltip: 'Holat filtri',
                onSelected: (value) =>
                    setState(() => _memberStatusFilter = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'active', child: Text('Faol xodimlar')),
                  PopupMenuItem(
                    value: 'inactive',
                    child: Text('Ishdan olinganlar'),
                  ),
                  PopupMenuItem(value: 'all', child: Text('Barchasi')),
                ],
                child: IconButton.filledTonal(
                  onPressed: () {},
                  icon: Icon(
                    _memberStatusFilter == 'active'
                        ? Icons.filter_list_rounded
                        : Icons.filter_alt_rounded,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Xodim qo‘shish',
                onPressed: _invite,
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            ],
          ),
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${filteredMembers.length} xodim',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: _showRoleManager,
                icon: const Icon(Icons.badge_outlined, size: 17),
                label: Text('${_roles.length} lavozim'),
              ),
            ],
          ),
          if (filteredMembers.isEmpty)
            const AppEmptyState(
              message: 'Bu qidiruv bo‘yicha xodim topilmadi.',
              icon: Icons.person_search_outlined,
            )
          else
            ...filteredMembers.map(_memberTile),
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

  Future<void> _showRoleManager() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Lavozimlar',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                if (_roles.isEmpty)
                  IconButton(
                    tooltip: 'Standart lavozimlar',
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _bootstrapDefaultRoles();
                    },
                    icon: const Icon(Icons.auto_awesome_rounded),
                  ),
                IconButton(
                  tooltip: 'Lavozim qo‘shish',
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    await _editRole();
                  },
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (_roles.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Hozircha lavozim yaratilmagan.'),
              )
            else
              ..._roles.map(_roleTile),
          ],
        ),
      ),
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
