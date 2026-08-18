part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskKpiViews on _TaskKpiPageState {
  Widget _buildPage(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    final spacing = context.appSpacing;
    final visibleTasks = _visibleTasks;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.all(spacing.md),
            children: [
              _buildTaskFilters(),
              SizedBox(height: spacing.sm),
              if (_tasks.isEmpty)
                const AppEmptyState(
                  message: 'Hozircha vazifa yo‘q.',
                  icon: Icons.task_alt_outlined,
                )
              else if (visibleTasks.isEmpty)
                const AppEmptyState(
                  message: 'Qidiruv yoki filtrga mos vazifa topilmadi.',
                  icon: Icons.search_off_rounded,
                )
              else
                ...visibleTasks.map(_taskTile),
              if (_hasMore) ...[
                SizedBox(height: spacing.sm),
                Center(
                  child: TextButton.icon(
                    onPressed: _loadingMore ? null : () => _load(append: true),
                    icon: _loadingMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.expand_more_rounded),
                    label: const Text('Yana yuklash'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _taskTile(Map<String, dynamic> task) => Card(
    child: ListTile(
      leading: Icon(_statusIcon(task['status'] as String? ?? 'todo')),
      title: Text(task['title'] as String? ?? ''),
      subtitle: Text(
        '${task['assignee_name'] as String? ?? 'Biriktirilmagan'}${_taskMeta(task).isEmpty ? '' : ' • ${_taskMeta(task)}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _statusPill(task['status'] as String? ?? 'todo'),
      onTap: () => _showTaskDetail(task),
    ),
  );

  Future<void> _openNotifications() async {
    final notifications = List<Map<String, dynamic>>.from(_notifications);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.72,
          child: notifications.isEmpty
              ? const Center(child: Text('Yangi bildirishnoma yo‘q.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, index) {
                    final item = notifications[index];
                    final activity = item['activity'] is Map
                        ? Map<String, dynamic>.from(item['activity'] as Map)
                        : const <String, dynamic>{};
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.task_alt_rounded),
                      ),
                      title: Text(item['task_title'] as String? ?? 'Vazifa'),
                      subtitle: Text(
                        activity['body'] as String? ?? 'Vazifa yangilandi.',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () async {
                        Navigator.pop(sheetContext);
                        final taskId = (item['task_id'] as num?)?.toInt();
                        if (taskId == null) return;
                        final task = _tasks
                            .cast<Map<String, dynamic>?>()
                            .firstWhere(
                              (value) => value?['id'] == taskId,
                              orElse: () => null,
                            );
                        if (task != null) await _showTaskDetail(task);
                      },
                    );
                  },
                ),
        ),
      ),
    );
    if (_unreadNotifications > 0) {
      try {
        await widget.repository.post('/task-kpi/notifications/read', {});
      } catch (_) {
        // The inbox remains usable if marking read is temporarily offline.
      }
      if (mounted) {
        setState(() {
          _unreadNotifications = 0;
          _notifications = _notifications
              .map(
                (item) => {
                  ...item,
                  'read_at': DateTime.now().toUtc().toIso8601String(),
                },
              )
              .toList(growable: false);
        });
      }
    }
  }
}
