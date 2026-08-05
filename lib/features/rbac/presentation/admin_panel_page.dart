import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/network/api_client.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  bool _loading = true;
  bool _isAdmin = false;
  String? _error;
  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _members = const [];

  @override
  void initState() {
    super.initState();
    _load();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invite,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Xodim qo‘shish'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.all(spacing.md),
          children: [
            AppSurfaceCard(
              backgroundColor: context.appColors.primarySoft,
              child: const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.admin_panel_settings_rounded),
                title: Text('Xodimlar va lavozimlar'),
                subtitle: Text(
                  'Lavozim, ko‘rish doirasi va ish holatini shu yerda boshqaring.',
                ),
              ),
            ),
            SizedBox(height: spacing.lg),
            AppSectionHeader(
              title: 'Lavozimlar',
              subtitle: '1 — eng yuqori daraja.',
              trailing: IconButton.filledTonal(
                onPressed: _editRole,
                icon: const Icon(Icons.add_rounded),
              ),
            ),
            SizedBox(height: spacing.xs),
            for (final role in _roles) _roleTile(role),
            if (_roles.isEmpty)
              const AppEmptyState(
                message: 'Lavozim yarating: Direktor, Menejer, Xodim.',
                icon: Icons.badge_outlined,
              ),
            SizedBox(height: spacing.lg),
            AppSectionHeader(
              title: 'Xodimlar',
              subtitle: '${_members.length} ta faol xodim',
            ),
            SizedBox(height: spacing.xs),
            for (final member in _members) _memberTile(member),
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
      trailing: IconButton(
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _editRole(role: role),
      ),
    ),
  );

  Widget _memberTile(Map<String, dynamic> member) {
    final role = member['role'] as Map<String, dynamic>?;
    return Card(
      child: ListTile(
        leading: AppAvatar(label: member['display_name'] as String? ?? ''),
        title: Text(member['display_name'] as String? ?? ''),
        subtitle: Text(role?['name'] as String? ?? 'Lavozim berilmagan'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'role') _assignRole(member);
            if (value == 'fire') _deactivate(member);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'role', child: Text('Lavozim tayinlash')),
            PopupMenuItem(value: 'fire', child: Text('Ishdan olish')),
          ],
        ),
      ),
    );
  }

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
    await _run(() async {
      await widget.apiClient.post('/rbac/invitations', {'email': value});
    });
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

  Future<void> _assignRole(Map<String, dynamic> member) async {
    final role = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Lavozim tanlang')),
          ..._roles.map(
            (item) => ListTile(
              title: Text(item['name'] as String),
              subtitle: Text(_visibilityLabel(item['visibility'] as String)),
              onTap: () => Navigator.pop(context, item),
            ),
          ),
        ],
      ),
    );
    if (role == null) return;
    await _run(() async {
      await widget.apiClient.put('/rbac/members/${member['member_id']}/role', {
        'role_id': role['id'],
      });
    });
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
}
