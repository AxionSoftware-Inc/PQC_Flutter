import 'package:flutter/material.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/network/api_client.dart';

/// Optional Task/KPI module shell. Its APIs are supplied by the independent
/// `task_kpi` backend plugin, not by chat or crypto core.
class TaskKpiPage extends StatefulWidget {
  const TaskKpiPage({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<TaskKpiPage> createState() => _TaskKpiPageState();
}

class _TaskKpiPageState extends State<TaskKpiPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tasks = const [];
  List<Map<String, dynamic>> _goals = const [];

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
      final values = await Future.wait<dynamic>([
        widget.apiClient.get('/task-kpi/tasks'),
        widget.apiClient.get('/task-kpi/kpi-goals'),
      ]);
      if (!mounted) return;
      setState(() {
        _tasks = List<Map<String, dynamic>>.from(values[0] as List);
        _goals = List<Map<String, dynamic>>.from(values[1] as List);
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

  @override
  Widget build(BuildContext context) {
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
    final done = _tasks.where((task) => task['status'] == 'done').length;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.all(spacing.md),
            children: [
              AppSectionHeader(
                title: 'Vazifalar',
                subtitle: '$done / ${_tasks.length} bajarilgan',
              ),
              SizedBox(height: spacing.xs),
              if (_tasks.isEmpty)
                const AppEmptyState(
                  message: 'Hozircha vazifa yo‘q.',
                  icon: Icons.task_alt_outlined,
                )
              else
                ..._tasks.map(_taskTile),
              SizedBox(height: spacing.lg),
              AppSectionHeader(title: 'KPI ko‘rsatkichlari'),
              SizedBox(height: spacing.xs),
              if (_goals.isEmpty)
                const AppEmptyState(
                  message: 'KPI ko‘rsatkichi belgilanmagan.',
                  icon: Icons.insights_outlined,
                )
              else
                ..._goals.map(_goalTile),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: _createTask,
            icon: const Icon(Icons.add_task_rounded),
            label: const Text('Vazifa qo‘shish'),
          ),
        ),
      ],
    );
  }

  Widget _taskTile(Map<String, dynamic> task) => Card(
    child: ListTile(
      leading: Icon(_statusIcon(task['status'] as String? ?? 'todo')),
      title: Text(task['title'] as String? ?? ''),
      subtitle: Text(task['assignee_name'] as String? ?? 'Biriktirilmagan'),
      trailing: Text(_statusLabel(task['status'] as String? ?? 'todo')),
      onTap: () => _advanceTask(task),
    ),
  );

  Widget _goalTile(Map<String, dynamic> goal) {
    final progress = (goal['progress'] as num? ?? 0).toDouble() / 100;
    return Card(
      child: ListTile(
        title: Text(goal['title'] as String? ?? ''),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(value: progress.clamp(0, 1)),
        ),
        trailing: Text('${goal['progress'] ?? 0}%'),
      ),
    );
  }

  Future<void> _createTask() async {
    final title = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yangi vazifa'),
        content: TextField(
          controller: title,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Vazifa nomi'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Bekor qilish'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, title.text.trim()),
            child: const Text('Yaratish'),
          ),
        ],
      ),
    );
    if (value?.isEmpty != false) {
      return;
    }
    try {
      await widget.apiClient.post('/task-kpi/tasks', {'title': value});
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
      'todo' => 'in_progress',
      'in_progress' => 'review',
      'review' => 'done',
      _ => null,
    };
    if (next == null) {
      return;
    }
    try {
      await widget.apiClient.patch('/task-kpi/tasks/${task['id']}', {
        'status': next,
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

  IconData _statusIcon(String value) => switch (value) {
    'done' => Icons.task_alt_rounded,
    'in_progress' => Icons.pending_actions_rounded,
    'review' => Icons.rate_review_outlined,
    _ => Icons.radio_button_unchecked_rounded,
  };

  String _statusLabel(String value) => switch (value) {
    'in_progress' => 'Jarayonda',
    'review' => 'Tekshiruvda',
    'done' => 'Bajarildi',
    'cancelled' => 'Bekor qilingan',
    _ => 'Kutilmoqda',
  };
}
