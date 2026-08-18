part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member


extension _TaskKpiAnalyticsFilters on _TaskKpiPageState {

  Widget _buildTaskFilters() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 350),
                () => _load(),
              );
            },
            decoration: InputDecoration(
              hintText: 'Vazifalarni qidirish',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                        unawaited(_load());
                      },
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Stack(
          clipBehavior: Clip.none,
          children: [
            PopupMenuButton<String>(
              tooltip: 'Status bo‘yicha filtr',
              initialValue: _statusFilter,
              onSelected: (value) {
                if (value == '_notifications') {
                  unawaited(_openNotifications());
                  return;
                }
                if (value == '_kpi') {
                  unawaited(_openKpiAnalytics());
                  return;
                }
                setState(() => _statusFilter = value);
                unawaited(_load());
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('Faol vazifalar')),
                PopupMenuItem(value: 'todo', child: Text('Yangi')),
                PopupMenuItem(value: 'in_progress', child: Text('Jarayonda')),
                PopupMenuItem(value: 'submitted', child: Text('Tekshiruvda')),
                PopupMenuItem(value: 'done', child: Text('Tugallangan')),
                PopupMenuItem(value: 'all', child: Text('Barchasi')),
                PopupMenuItem(
                  value: '_notifications',
                  child: Text('Bildirishnomalar'),
                ),
                PopupMenuItem(value: '_kpi', child: Text('KPI analitikasi')),
              ],
              icon: Icon(
                _statusFilter == 'open' || _statusFilter == 'all'
                    ? Icons.filter_list_rounded
                    : Icons.filter_alt_rounded,
              ),
            ),
            if (_unreadNotifications > 0)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.appColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (_assignees.isNotEmpty) ...[
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Yangi vazifa',
            onPressed: _openCreateTaskPage,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ],
    );
  }

  Widget _statusPill(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _taskMeta(Map<String, dynamic> task) {
    final due = task['due_at']?.toString();
    final priority = task['priority'] as String? ?? 'normal';
    final parts = <String>[];
    if (due?.isNotEmpty == true) parts.add('Muddat: ${_formatDate(due!)}');
    if (priority != 'normal') parts.add(_priorityLabel(priority));
    return parts.join(' • ');
  }

  // ignore: unused_element

}
