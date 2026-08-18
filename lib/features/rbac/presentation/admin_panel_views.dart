part of 'admin_panel_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AdminPanelViews on _AdminPanelPageState {
  Widget _buildPage(BuildContext context) {
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
                  PopupMenuItem(
                    value: 'unassigned',
                    child: Text('Lavozimsizlar'),
                  ),
                  PopupMenuItem(value: 'all', child: Text('Barchasi')),
                ],
                icon: Icon(
                  _memberStatusFilter == 'active'
                      ? Icons.filter_list_rounded
                      : Icons.filter_alt_rounded,
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Xodim qo‘shish',
                onPressed: _addRegisteredUser,
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.person_add_alt_1_rounded),
                    if (_registeredUserCount > 0)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
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
    if (!widget.standalone) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin panel'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: content,
    );
  }
}
