part of 'task_kpi_page.dart';

extension _TaskKpiTaskActions on _TaskKpiPageState {
  Future<void> _showTaskDetail(Map<String, dynamic> task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TaskDetailPage(
          repository: widget.repository,
          currentUserId: widget.currentUserId,
          onOpenKpiChat: widget.onOpenKpiChat,
          task: task,
          canReview: ((task['permissions'] as Map?)?['can_manage'] == true),
          onAdvance: () => _advanceTask(task),
          onReview: (accepted) => _reviewTask(task, accepted: accepted),
          onDownloadAttachment: _downloadTaskAttachment,
        ),
      ),
    );
    if (mounted) await _load();
    return;
  }

  Future<void> _reviewTask(
    Map<String, dynamic> task, {
    required bool accepted,
  }) async {
    String? reviewNote;
    if (!accepted) {
      final controller = TextEditingController();
      reviewNote = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Qayta ishlash sababi'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Nimani tuzatish kerakligini yozing',
              alignLabelWithHint: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Qaytarish'),
            ),
          ],
        ),
      );
      if (reviewNote?.trim().isEmpty != false) return;
    }
    try {
      await widget.repository.patch('/task-kpi/tasks/${task['id']}', {
        'status': accepted ? 'done' : 'returned',
        ...?reviewNote == null ? null : {'review_note': reviewNote},
      });
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _advanceTask(Map<String, dynamic> task) async {
    final current = task['status'] as String? ?? 'todo';
    final next = switch (current) {
      'todo' => 'accepted',
      'accepted' => 'in_progress',
      'returned' => 'in_progress',
      'in_progress' => 'submitted',
      _ => null,
    };
    if (next == null) {
      return;
    }
    String? note;
    if (next == 'submitted') {
      final controller = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Ishni topshirish'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Bajarilgan ish bo‘yicha izoh',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Topshirish'),
            ),
          ],
        ),
      );
      if (note == null) return;
    }
    try {
      final payload = <String, dynamic>{'status': next};
      if (note != null) {
        payload['completion_note'] = note;
      }
      await widget.repository.patch('/task-kpi/tasks/${task['id']}', payload);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  IconData _statusIcon(String value) => switch (value) {
    'done' => Icons.task_alt_rounded,
    'accepted' => Icons.check_circle_outline_rounded,
    'in_progress' => Icons.pending_actions_rounded,
    'submitted' => Icons.rate_review_outlined,
    _ => Icons.radio_button_unchecked_rounded,
  };

  String _statusLabel(String value) => switch (value) {
    'accepted' => 'Qabul qilingan',
    'in_progress' => 'Jarayonda',
    'submitted' => 'Rahbar tekshiradi',
    'done' => 'Qabul qilindi',
    'returned' => 'Qayta ishlash kerak',
    'cancelled' => 'Bekor qilingan',
    _ => 'Kutilmoqda',
  };

  String _priorityLabel(String value) => switch (value) {
    'low' => 'Past',
    'high' => 'Yuqori',
    'urgent' => 'Shoshilinch',
    _ => 'Oddiy',
  };

  Color _statusColor(String value) => switch (value) {
    'done' => Colors.green,
    'accepted' => Colors.teal,
    'submitted' => Colors.orange,
    'in_progress' => Colors.blue,
    'cancelled' => Colors.red,
    _ => Colors.grey,
  };

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCreateTaskPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CreateTaskPage(
          repository: widget.repository,
          assignees: _assignees,
        ),
      ),
    );
    if (mounted) await _load();
  }
}
