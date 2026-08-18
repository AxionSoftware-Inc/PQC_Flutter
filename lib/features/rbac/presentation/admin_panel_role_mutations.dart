part of 'admin_panel_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _AdminPanelRoleMutations on _AdminPanelPageState {

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
        await widget.repository.post('/rbac/roles', body);
      } else {
        await widget.repository.patch('/rbac/roles/${role['id']}', body);
      }
    });
  }

  Future<void> _bootstrapDefaultRoles() async {
    await _run(() async {
      await widget.repository.post('/rbac/roles/bootstrap-defaults', {});
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
      await widget.repository.put('/rbac/members/${member['member_id']}/role', {
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
        await widget.repository.delete('/rbac/roles/${role['id']}');
      });
    }
  }


}
