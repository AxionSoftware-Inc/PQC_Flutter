import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

class _TaskDetailPage extends StatelessWidget {
  const _TaskDetailPage({
    required this.task,
    required this.canReview,
    required this.onAdvance,
    required this.onReview,
    required this.onDownloadAttachment,
  });

  final Map<String, dynamic> task;
  final bool canReview;
  final Future<void> Function() onAdvance;
  final Future<void> Function(bool accepted) onReview;
  final Future<void> Function(Map<String, dynamic> attachment)
  onDownloadAttachment;

  String _statusLabel(String value) => switch (value) {
    'accepted' => 'Qabul qilingan',
    'in_progress' => 'Jarayonda',
    'submitted' => 'Rahbar tekshiradi',
    'done' => 'Tugatildi',
    'returned' => 'Qayta ishlash kerak',
    'cancelled' => 'Bekor qilingan',
    _ => 'Yangi',
  };

  String _priorityLabel(String value) => switch (value) {
    'low' => 'Past',
    'high' => 'Yuqori',
    'urgent' => 'Shoshilinch',
    _ => 'Oddiy',
  };

  String _formatDate(String value) {
    final parsed = DateTime.tryParse(value)?.toLocal();
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}.${parsed.month.toString().padLeft(2, '0')}.${parsed.year} ${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final status = task['status'] as String? ?? 'todo';
    final description = task['description'] as String? ?? '';
    final attachments = (task['attachments'] as List?) ?? const [];
    final permissions =
        (task['permissions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    final canAdvance =
        permissions.isEmpty || permissions['is_assignee'] == true;
    final actionLabel = switch (status) {
      'todo' when canAdvance => 'Qabul qildim',
      'accepted' when canAdvance => 'Ishni boshladim',
      'returned' when canAdvance => 'Qayta ishlashni boshlash',
      'in_progress' when canAdvance => 'Ishni topshirish',
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Vazifa tafsilotlari')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(spacing.md),
          children: [
            Text(
              task['title'] as String? ?? '',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.sm),
            Wrap(
              spacing: spacing.xs,
              runSpacing: spacing.xs,
              children: [
                Chip(label: Text(_statusLabel(status))),
                Chip(
                  label: Text(
                    _priorityLabel(task['priority'] as String? ?? 'normal'),
                  ),
                ),
              ],
            ),
            SizedBox(height: spacing.md),
            if (description.trim().isNotEmpty)
              AppSurfaceCard(
                child: Text(
                  description,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            SizedBox(height: spacing.md),
            _infoRow(
              context,
              'Bajaruvchi',
              task['assignee_name'] as String? ?? '—',
            ),
            if (task['due_at']?.toString().isNotEmpty == true)
              _infoRow(
                context,
                'Deadline',
                _formatDate(task['due_at'] as String),
              ),
            if (task['completion_note']?.toString().isNotEmpty == true)
              _infoRow(
                context,
                'Xodim izohi',
                task['completion_note'] as String,
              ),
            if (task['review_note']?.toString().isNotEmpty == true)
              _infoRow(context, 'Rahbar izohi', task['review_note'] as String),
            if (attachments.isNotEmpty) ...[
              SizedBox(height: spacing.md),
              Text(
                'Biriktirilgan fayllar',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...attachments.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_rounded),
                  title: Text(item['filename'] as String? ?? 'Fayl'),
                  subtitle: Text(_formatBytes(item['size_bytes'] as int? ?? 0)),
                  trailing: IconButton(
                    tooltip: 'Yuklab olish',
                    onPressed: () => onDownloadAttachment(
                      Map<String, dynamic>.from(item as Map),
                    ),
                    icon: const Icon(Icons.download_rounded),
                  ),
                ),
              ),
            ],
            SizedBox(height: spacing.lg),
            if (status == 'submitted' && canReview) ...[
              FilledButton.icon(
                onPressed: () async {
                  await onReview(true);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.check_rounded),
                label: const Text('Tugatildi deb qabul qilish'),
              ),
              SizedBox(height: spacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  await onReview(false);
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Qayta ishlashga qaytarish'),
              ),
            ] else if (actionLabel != null)
              FilledButton.icon(
                onPressed: () async {
                  await onAdvance();
                  if (context.mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(actionLabel),
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _CreateTaskPage extends StatefulWidget {
  const _CreateTaskPage({required this.apiClient, required this.assignees});

  final ApiClient apiClient;
  final List<Map<String, dynamic>> assignees;

  @override
  State<_CreateTaskPage> createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<_CreateTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _assigneeId;
  String _priority = 'normal';
  DateTime? _dueAt;
  PlatformFile? _attachment;
  bool _saving = false;

  /// The assignee endpoint is scoped by workspace, but older server builds
  /// could return the same member more than once after a role change. Keep the
  /// picker deterministic and show each employee only once.
  List<Map<String, dynamic>> get _uniqueAssignees {
    final byMemberId = <int, Map<String, dynamic>>{};
    for (final member in widget.assignees) {
      final id = (member['member_id'] as num?)?.toInt();
      if (id != null) {
        byMemberId.putIfAbsent(id, () => member);
      }
    }
    return byMemberId.values.toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    final assignees = _uniqueAssignees;
    if (assignees.isNotEmpty) {
      _assigneeId = (assignees.first['member_id'] as num?)?.toInt();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      initialDate: _dueAt ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: _dueAt == null
          ? TimeOfDay.now()
          : TimeOfDay.fromDateTime(_dueAt!),
    );
    if (time == null) return;
    setState(() {
      _dueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _assigneeId == null) return;
    setState(() => _saving = true);
    try {
      final created = await widget.apiClient.post('/task-kpi/tasks', {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'assignee_id': _assigneeId,
        'priority': _priority,
        if (_dueAt != null) 'due_at': _dueAt!.toUtc().toIso8601String(),
      });
      if (_attachment != null && created is Map && created['id'] != null) {
        final file = _attachment!;
        final files = file.path != null
            ? [
                await http.MultipartFile.fromPath(
                  'file',
                  file.path!,
                  filename: file.name,
                ),
              ]
            : [
                http.MultipartFile.fromBytes(
                  'file',
                  file.bytes ?? const [],
                  filename: file.name,
                ),
              ];
        await widget.apiClient.multipartPost(
          '/task-kpi/tasks/${created['id']}/attachments',
          files: files,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yangi vazifa'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Saqlash'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.all(spacing.md),
            children: [
              TextFormField(
                controller: _titleController,
                autofocus: true,
                maxLines: 2,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Vazifa nomi',
                  hintText: 'Masalan: Haftalik hisobotni tayyorlash',
                ),
                validator: (value) => value?.trim().isEmpty == true
                    ? 'Vazifa nomini kiriting'
                    : null,
              ),
              SizedBox(height: spacing.md),
              TextFormField(
                controller: _descriptionController,
                minLines: 6,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Vazifa tafsiloti',
                  hintText:
                      'Nima qilish kerakligi va kutilayotgan natijani yozing',
                  alignLabelWithHint: true,
                ),
              ),
              SizedBox(height: spacing.lg),
              Text('Bajaruvchi', style: Theme.of(context).textTheme.titleSmall),
              SizedBox(height: spacing.xs),
              DropdownButtonFormField<int>(
                initialValue: _assigneeId,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                items: _uniqueAssignees.map((member) {
                  final name = member['name'] as String? ?? 'Xodim';
                  final role =
                      member['role_name'] as String? ?? 'Lavozim belgilanmagan';
                  return DropdownMenuItem<int>(
                    value: (member['member_id'] as num).toInt(),
                    child: Row(
                      children: [
                        AppAvatar(
                          label: name,
                          imageUrl: member['avatar_url'] as String?,
                          radius: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, overflow: TextOverflow.ellipsis),
                              Text(
                                role,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) => setState(() => _assigneeId = value),
                validator: (_) =>
                    _assigneeId == null ? 'Bajaruvchini tanlang' : null,
              ),
              SizedBox(height: spacing.lg),
              Text(
                'Muhimlik va muddat',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              SizedBox(height: spacing.xs),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('Past')),
                        DropdownMenuItem(value: 'normal', child: Text('Oddiy')),
                        DropdownMenuItem(value: 'high', child: Text('Yuqori')),
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('Shoshilinch'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? 'normal'),
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDeadline,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _dueAt == null ? 'Deadline' : _formatDate(_dueAt!),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: spacing.md),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    withData: false,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    setState(() => _attachment = result.files.first);
                  }
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  _attachment == null
                      ? 'Fayl biriktirish (ixtiyoriy)'
                      : _attachment!.name,
                ),
              ),
              if (_saving) ...[
                SizedBox(height: spacing.md),
                const LinearProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _TaskKpiPageState extends State<TaskKpiPage> {
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<Map<String, dynamic>> _tasks = const [];
  List<Map<String, dynamic>> _assignees = const [];
  List<Map<String, dynamic>> _notifications = const [];
  List<Map<String, dynamic>> _kpiSummary = const [];
  int _unreadNotifications = 0;
  int? _nextOffset;
  bool _hasMore = false;
  final TextEditingController _searchController = TextEditingController();
  String _statusFilter = 'all';
  Timer? _searchDebounce;
  Timer? _refreshTimer;

  List<Map<String, dynamic>> get _visibleTasks {
    final query = _searchController.text.trim().toLowerCase();
    return _tasks.where((task) {
      final status = task['status'] as String? ?? 'todo';
      final title = (task['title'] as String? ?? '').toLowerCase();
      final description = (task['description'] as String? ?? '').toLowerCase();
      final matchesStatus = _statusFilter == 'all' || status == _statusFilter;
      return matchesStatus &&
          (query.isEmpty ||
              title.contains(query) ||
              description.contains(query));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && !_loading && !_loadingMore) unawaited(_load());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<dynamic> _optionalGet(String path) async {
    try {
      return await widget.apiClient.get(path);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _extractTaskItems(dynamic response) {
    final raw = response is Map ? response['items'] : response;
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _dedupeAssignees(dynamic response) {
    if (response is! List) return const [];
    final byMemberId = <int, Map<String, dynamic>>{};
    for (final raw in response) {
      if (raw is! Map) continue;
      final member = Map<String, dynamic>.from(raw);
      final id = (member['member_id'] as num?)?.toInt();
      if (id != null) byMemberId.putIfAbsent(id, () => member);
    }
    return byMemberId.values.toList(growable: false);
  }

  Future<void> _load({bool append = false}) async {
    if (append && (_loadingMore || !_hasMore || _nextOffset == null)) return;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
        _nextOffset = 0;
        _hasMore = false;
      }
    });
    try {
      final query = <String, String>{
        'offset': '${append ? _nextOffset : 0}',
        'limit': '50',
        if (_statusFilter != 'all') 'status': _statusFilter,
        if (_searchController.text.trim().isNotEmpty)
          'q': _searchController.text.trim(),
      };
      final values = append
          ? await Future.wait<dynamic>([
              widget.apiClient.get('/task-kpi/tasks', queryParameters: query),
            ])
          : await Future.wait<dynamic>([
              widget.apiClient.get('/task-kpi/tasks', queryParameters: query),
              widget.apiClient.get('/task-kpi/assignees'),
              _optionalGet('/task-kpi/notifications'),
              _optionalGet('/task-kpi/kpi-summary'),
            ]);
      final taskResponse = values[0];
      final taskItems = _extractTaskItems(taskResponse);
      final taskPage = taskResponse is Map
          ? Map<String, dynamic>.from(taskResponse)
          : const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _tasks = append ? [..._tasks, ...taskItems] : taskItems;
        if (!append) {
          _assignees = _dedupeAssignees(values[1]);
          final notifications = values[2];
          if (notifications is Map) {
            _unreadNotifications =
                (notifications['unread_count'] as num?)?.toInt() ?? 0;
            _notifications = notifications['items'] is List
                ? List<Map<String, dynamic>>.from(
                    notifications['items'] as List,
                  )
                : const [];
          }
          _kpiSummary = values[3] is List
              ? List<Map<String, dynamic>>.from(values[3] as List)
              : const [];
        }
        _hasMore = taskPage['has_more'] == true;
        _nextOffset = taskPage['next_offset'] as int?;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
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
    final visibleTasks = _visibleTasks;
    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: EdgeInsets.all(spacing.md),
            children: [
              _buildTaskToolbar(),
              SizedBox(height: spacing.sm),
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

  Widget _buildTaskToolbar() {
    final spacing = context.appSpacing;
    return Row(
      children: [
        Expanded(
          child: Text(
            _tasks.isEmpty ? 'Vazifalar' : '${_tasks.length} ta vazifa',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'KPI ko‘rsatkichlari',
          onPressed: _openKpiAnalytics,
          icon: const Icon(Icons.insights_rounded),
        ),
        SizedBox(width: spacing.xs),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton.filledTonal(
              tooltip: 'Vazifa bildirishnomalari',
              onPressed: _openNotifications,
              icon: const Icon(Icons.notifications_none_rounded),
            ),
            if (_unreadNotifications > 0)
              Positioned(
                right: 0,
                top: -2,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.appColors.danger,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

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
        await widget.apiClient.post('/task-kpi/notifications/read', {});
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

  Future<void> _openKpiAnalytics() async {
    try {
      final values = await Future.wait<dynamic>([
        widget.apiClient.get('/task-kpi/kpi-summary'),
        widget.apiClient.get('/task-kpi/reports'),
        widget.apiClient.get('/task-kpi/kpi-goals'),
      ]);
      if (!mounted) return;
      final summary = values[0] is List
          ? List<Map<String, dynamic>>.from(values[0] as List)
          : _kpiSummary;
      final report = values[1] is Map
          ? Map<String, dynamic>.from(values[1] as Map)
          : const <String, dynamic>{};
      final goals = values[2] is List
          ? List<Map<String, dynamic>>.from(values[2] as List)
          : const <Map<String, dynamic>>[];
      final goalDetails = await Future.wait<dynamic>(
        goals.map(
          (goal) => widget.apiClient.get('/task-kpi/kpi-goals/${goal['id']}'),
        ),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('KPI ko‘rsatkichlari'),
          content: SizedBox(
            width: 420,
            child: ListView(
              shrinkWrap: true,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricChip('Jami', report['total']),
                    _metricChip('Tugatilgan', report['done']),
                    _metricChip('Qaytarilgan', report['returned']),
                    _metricChip('Muddati o‘tgan', report['overdue']),
                  ],
                ),
                if (report['average_completion_hours'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'O‘rtacha bajarilish: ${report['average_completion_hours']} soat',
                    ),
                  ),
                const SizedBox(height: 16),
                ...summary.map((item) {
                  final total = (item['total'] as num?)?.toInt() ?? 0;
                  final done = (item['done'] as num?)?.toInt() ?? 0;
                  final progress = total == 0 ? 0.0 : done / total;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item['name'] as String? ?? 'Xodim'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: LinearProgressIndicator(value: progress),
                    ),
                    trailing: Text('$done/$total'),
                  );
                }),
                if (goals.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text(
                    'KPI maqsadlari',
                    style: Theme.of(dialogContext).textTheme.titleMedium,
                  ),
                  ...goals.asMap().entries.map((entry) {
                    final goal = entry.value;
                    final current =
                        (goal['current_value'] as num?)?.toDouble() ?? 0;
                    final target =
                        (goal['target_value'] as num?)?.toDouble() ?? 0;
                    final progress = target <= 0
                        ? 0.0
                        : (current / target).clamp(0, 1).toDouble();
                    final detail = goalDetails[entry.key];
                    final historyCount =
                        detail is Map && detail['history'] is List
                        ? (detail['history'] as List).length
                        : 0;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(goal['title'] as String? ?? 'KPI'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 4),
                          Text('Tarix: $historyCount ta o‘zgarish'),
                        ],
                      ),
                      trailing: Text('$current/$target'),
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Yopish'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('KPI ma’lumotlarini yuklab bo‘lmadi: $error')),
      );
    }
  }

  Widget _metricChip(String label, dynamic value) {
    return Chip(label: Text('$label: ${value ?? 0}'));
  }

  Future<void> _downloadTaskAttachment(Map<String, dynamic> attachment) async {
    final id = (attachment['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      final response = await widget.apiClient.getBytes(
        '/task-kpi/attachments/$id/download',
      );
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(root.path, 'task-kpi'));
      await directory.create(recursive: true);
      final rawName = attachment['filename'] as String? ?? 'attachment';
      final safeName = rawName.replaceAll(RegExp(r'[\\/]'), '_');
      final file = File(p.join(directory.path, '${id}_$safeName'));
      await file.writeAsBytes(response.bytes, flush: true);
      await OpenFilex.open(file.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Faylni yuklab bo‘lmadi: $error')));
    }
  }

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
        PopupMenuButton<String>(
          tooltip: 'Status bo‘yicha filtr',
          initialValue: _statusFilter,
          onSelected: (value) {
            setState(() => _statusFilter = value);
            unawaited(_load());
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'all', child: Text('Barchasi')),
            PopupMenuItem(value: 'todo', child: Text('Yangi')),
            PopupMenuItem(value: 'in_progress', child: Text('Jarayonda')),
            PopupMenuItem(value: 'submitted', child: Text('Tekshiruvda')),
            PopupMenuItem(value: 'done', child: Text('Qabul qilingan')),
          ],
          child: IconButton.filledTonal(
            onPressed: () {},
            icon: Icon(
              _statusFilter == 'all'
                  ? Icons.filter_list_rounded
                  : Icons.filter_alt_rounded,
            ),
          ),
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
  Widget _buildSummaryGrid() {
    return const SizedBox.shrink();
  }

  // ignore: unused_element
  Widget _buildKanban() {
    const columns = [
      ('todo', 'Yangi'),
      ('in_progress', 'Jarayonda'),
      ('submitted', 'Tekshiruv'),
      ('done', 'Qabul qilingan'),
    ];
    return SizedBox(
      height: 330,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: columns.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final column = columns[index];
          final tasks = _visibleTasks
              .where((task) => task['status'] == column.$1)
              .toList();
          return SizedBox(
            width: 260,
            child: AppSurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${column.$2} · ${tasks.length}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: tasks.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, itemIndex) => Material(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _showTaskDetail(tasks[itemIndex]),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tasks[itemIndex]['title'] as String? ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_taskMeta(tasks[itemIndex]).isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    _taskMeta(tasks[itemIndex]),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ignore: unused_element
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

  Future<void> _showTaskDetail(Map<String, dynamic> task) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _TaskDetailPage(
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

    // Legacy bottom-sheet implementation kept below only as a source
    // reference while old hot-reload sessions are still running.
    // ignore: dead_code
    final status = task['status'] as String? ?? 'todo';
    final action = _nextAction(status);
    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      // ignore: use_build_context_synchronously
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                task['title'] as String? ?? '',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(task['description'] as String? ?? ''),
              const SizedBox(height: 16),
              _detailLine(
                'Bajaruvchi',
                task['assignee_name'] as String? ?? '—',
              ),
              _detailLine('Holat', _statusLabel(status)),
              _detailLine(
                'Muhimlik',
                _priorityLabel(task['priority'] as String? ?? 'normal'),
              ),
              if (task['due_at']?.toString().isNotEmpty == true)
                _detailLine('Muddat', _formatDate(task['due_at'] as String)),
              if (task['completion_note']?.toString().isNotEmpty == true)
                _detailLine('Xodim izohi', task['completion_note'] as String),
              if (task['review_note']?.toString().isNotEmpty == true)
                _detailLine('Rahbar izohi', task['review_note'] as String),
              if ((task['attachments'] as List?)?.isNotEmpty == true) ...[
                const SizedBox(height: 10),
                Text(
                  'Biriktirilgan fayllar',
                  style: Theme.of(sheetContext).textTheme.titleSmall,
                ),
                for (final attachment in (task['attachments'] as List))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.attach_file_rounded),
                    title: Text(attachment['filename'] as String? ?? 'Fayl'),
                    subtitle: Text(
                      _formatBytes(attachment['size_bytes'] as int? ?? 0),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              if (status == 'submitted' && _assignees.isNotEmpty) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _reviewTask(task, accepted: true);
                    },
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Tugatildi deb qabul qilish'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _reviewTask(task, accepted: false);
                    },
                    icon: const Icon(Icons.replay_rounded),
                    label: const Text('Qayta ishlashga qaytarish'),
                  ),
                ),
              ] else if (action != null)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _confirmProgression(task);
                    },
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: Text(action),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
      await widget.apiClient.patch('/task-kpi/tasks/${task['id']}', {
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

  Future<void> _confirmProgression(Map<String, dynamic> task) async {
    final status = task['status'] as String? ?? 'todo';
    if (status == 'todo' || status == 'accepted') {
      final isAccepting = status == 'todo';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(isAccepting ? 'Vazifani qabul qilish' : 'Ishni boshlash'),
          content: Text(
            isAccepting
                ? 'Vazifa matni va biriktirilgan fayllarni ko‘rib chiqdim. Vazifani qabul qilaman.'
                : 'Vazifani bajarishni boshlaysizmi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(isAccepting ? 'Qabul qildim' : 'Boshladim'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _advanceTask(task);
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 112, child: Text(label)),
        Expanded(child: Text(value)),
      ],
    ),
  );

  String? _nextAction(String status) => switch (status) {
    'todo' => 'Qabul qildim',
    'accepted' => 'Ishni boshladim',
    'returned' => 'Qayta ishlashni boshlash',
    'in_progress' => 'Ishni topshirish',
    _ => null,
  };

  // Kept as a compatibility fallback for older callers; the visible action
  // now opens the dedicated create page above.
  // ignore: unused_element
  Future<void> _createTask() async {
    final title = TextEditingController();
    final description = TextEditingController();
    var assigneeId = _assignees.isEmpty
        ? null
        : _assignees.first['member_id'] as int;
    var priority = 'normal';
    DateTime? dueAt;
    PlatformFile? attachment;
    final value = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Yangi vazifa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Vazifa nomi'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: description,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Vazifa matni va kutilayotgan natija',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: assigneeId,
                  items: _assignees
                      .map(
                        (member) => DropdownMenuItem(
                          value: member['member_id'] as int,
                          child: Text(member['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => update(() => assigneeId = value),
                  decoration: const InputDecoration(labelText: 'Bajaruvchi'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: priority,
                  items: const [
                    DropdownMenuItem(
                      value: 'low',
                      child: Text('Past ustuvorlik'),
                    ),
                    DropdownMenuItem(
                      value: 'normal',
                      child: Text('Oddiy ustuvorlik'),
                    ),
                    DropdownMenuItem(
                      value: 'high',
                      child: Text('Yuqori ustuvorlik'),
                    ),
                    DropdownMenuItem(
                      value: 'urgent',
                      child: Text('Shoshilinch'),
                    ),
                  ],
                  onChanged: (value) =>
                      update(() => priority = value ?? 'normal'),
                  decoration: const InputDecoration(labelText: 'Ustuvorlik'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    dueAt == null
                        ? 'Muddat belgilanmagan'
                        : _formatDate(dueAt!.toIso8601String()),
                  ),
                  trailing: dueAt == null
                      ? const Icon(Icons.chevron_right_rounded)
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => update(() => dueAt = null),
                        ),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: dueAt ?? DateTime.now(),
                    );
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (time == null) return;
                    update(
                      () => dueAt = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ),
                    );
                  },
                ),
                TextButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      withData: false,
                    );
                    if (result != null && result.files.isNotEmpty) {
                      update(() => attachment = result.files.first);
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(
                    attachment == null
                        ? 'Fayl biriktirish (ixtiyoriy)'
                        : attachment!.name,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Bekor qilish'),
            ),
            FilledButton(
              onPressed: assigneeId == null
                  ? null
                  : () => Navigator.pop(context, {
                      'title': title.text.trim(),
                      'description': description.text.trim(),
                      'assignee_id': assigneeId,
                      'priority': priority,
                      'due_at': dueAt?.toUtc().toIso8601String(),
                      'attachment': attachment,
                    }),
              child: const Text('Yaratish'),
            ),
          ],
        ),
      ),
    );
    if (value == null || (value['title'] as String? ?? '').isEmpty) {
      return;
    }
    try {
      final created = await widget.apiClient.post('/task-kpi/tasks', {
        'title': value['title'],
        'description': value['description'],
        'assignee_id': value['assignee_id'],
        'priority': value['priority'],
        if (value['due_at'] != null) 'due_at': value['due_at'],
      });
      final selected = value['attachment'] as PlatformFile?;
      if (selected != null && created is Map && created['id'] != null) {
        final files = selected.path != null
            ? [
                await http.MultipartFile.fromPath(
                  'file',
                  selected.path!,
                  filename: selected.name,
                ),
              ]
            : [
                http.MultipartFile.fromBytes(
                  'file',
                  selected.bytes ?? const [],
                  filename: selected.name,
                ),
              ];
        await widget.apiClient.multipartPost(
          '/task-kpi/tasks/${created['id']}/attachments',
          files: files,
        );
      }
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
      await widget.apiClient.patch('/task-kpi/tasks/${task['id']}', payload);
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _openCreateTaskPage() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            _CreateTaskPage(apiClient: widget.apiClient, assignees: _assignees),
      ),
    );
    if (mounted) await _load();
  }
}
