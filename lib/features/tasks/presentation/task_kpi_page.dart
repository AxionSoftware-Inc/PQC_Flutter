import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../app/design_system/app_design_system.dart';
import '../../../core/network/api_client.dart';
import '../../chat/presentation/chat_thread_widget.dart';

/// Optional Task/KPI module shell. Its APIs are supplied by the independent
/// `task_kpi` backend plugin, not by chat or crypto core.
class TaskKpiPage extends StatefulWidget {
  const TaskKpiPage({
    super.key,
    required this.apiClient,
    required this.currentUserId,
  });

  final ApiClient apiClient;
  final int currentUserId;

  @override
  State<TaskKpiPage> createState() => _TaskKpiPageState();
}

class _TaskDetailPage extends StatefulWidget {
  const _TaskDetailPage({
    required this.apiClient,
    required this.currentUserId,
    required this.task,
    required this.canReview,
    required this.onAdvance,
    required this.onReview,
    required this.onDownloadAttachment,
  });

  final ApiClient apiClient;
  final int currentUserId;
  final Map<String, dynamic> task;
  final bool canReview;
  final Future<void> Function() onAdvance;
  final Future<void> Function(bool accepted) onReview;
  final Future<void> Function(Map<String, dynamic> attachment)
  onDownloadAttachment;

  @override
  State<_TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends State<_TaskDetailPage>
    with SingleTickerProviderStateMixin {
  static const _maxAttachmentBytes = 25 * 1024 * 1024;
  final TextEditingController _commentController = TextEditingController();
  late final TabController _tabController;
  List<Map<String, dynamic>> _activities = const [];
  List<PlatformFile> _selectedAttachments = const [];
  Map<String, dynamic>? _replyTarget;
  final Set<int> _openingFileIds = <int>{};
  Timer? _activityRefreshTimer;
  bool _loadingActivities = true;
  bool _sendingUpdate = false;
  String? _activityError;

  Map<String, dynamic> get task => widget.task;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    unawaited(_loadActivities());
    _activityRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_loadingActivities) {
        unawaited(_loadActivities(silent: true));
      }
    });
  }

  void _onTabChanged() {
    if (!mounted || _tabController.indexIsChanging) return;
    setState(() {});
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();
    _activityRefreshTimer?.cancel();
    _commentController.dispose();
    super.dispose();
  }

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

  Future<void> _loadActivities({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loadingActivities = true);
    try {
      final response = await widget.apiClient.get(
        '/task-kpi/tasks/${task['id']}/activity',
      );
      if (!mounted) return;
      setState(() {
        _activities = response is List
            ? response
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : const [];
        _activityError = null;
        _loadingActivities = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activityError = error.toString();
        _loadingActivities = false;
      });
    }
  }

  Future<void> _pickActivityAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !mounted) return;
    final existing = _selectedAttachments
        .map((file) => '${file.name}:${file.size}')
        .toSet();
    final added = result.files
        .where((file) => file.size > 0)
        .where((file) => existing.add('${file.name}:${file.size}'))
        .toList();
    final oversized = added.where((file) => file.size > _maxAttachmentBytes);
    if (oversized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${oversized.first.name} hajmi 25 MB dan oshmasligi kerak.',
          ),
        ),
      );
    }
    final valid = added
        .where((file) => file.size <= _maxAttachmentBytes)
        .toList();
    if (valid.isNotEmpty) {
      setState(() {
        _selectedAttachments = [..._selectedAttachments, ...valid];
      });
    }
  }

  Future<void> _sendUpdate() async {
    final body = _commentController.text.trim();
    if ((body.isEmpty && _selectedAttachments.isEmpty) || _sendingUpdate) {
      return;
    }
    setState(() => _sendingUpdate = true);
    try {
      if (body.isNotEmpty) {
        final payload = <String, dynamic>{'body': body};
        final replyId = (_replyTarget?['id'] as num?)?.toInt();
        final replyKind = _replyTarget?['kind']?.toString();
        final replyLabel = _replyTarget?['label']?.toString();
        if (replyId != null && replyKind != null) {
          final marker = replyKind == 'file' ? 'Faylga' : 'Izohga';
          final target = replyKind == 'file' ? 'file' : 'comment';
          payload['body'] =
              '$marker javob: $replyLabel [$target:$replyId]\n$body';
          payload['metadata'] = replyKind == 'file'
              ? {'reply_to_attachment_id': replyId}
              : {'reply_to_activity_id': replyId};
        }
        await widget.apiClient.post(
          '/task-kpi/tasks/${task['id']}/activity',
          payload,
        );
      }
      for (final file in _selectedAttachments) {
        await _uploadActivityAttachment(file);
      }
      _commentController.clear();
      if (mounted) {
        setState(() {
          _selectedAttachments = const [];
          _replyTarget = null;
        });
      }
      await _loadActivities();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _sendingUpdate = false);
    }
  }

  void _replyToAttachment(Map<String, dynamic> file) {
    setState(() {
      _replyTarget = {
        'id': file['id'],
        'kind': 'file',
        'label': file['filename'] ?? 'Fayl',
      };
    });
    _tabController.animateTo(1);
  }

  void _replyToActivity(Map<String, dynamic> activity) {
    final body = activity['body']?.toString().trim() ?? '';
    if (body.isEmpty) return;
    setState(() {
      _replyTarget = {
        'id': activity['id'],
        'kind': 'text',
        'label': body.split('\n').first,
      };
    });
    _tabController.animateTo(1);
  }

  List<Map<String, dynamic>> get _pinnedActivities => _activities
      .where((activity) => activity['is_pinned'] == true)
      .toList(growable: false);

  Future<void> _togglePin(Map<String, dynamic> activity) async {
    final id = (activity['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await widget.apiClient.post(
        '/task-kpi/tasks/${task['id']}/activity/$id/pin',
        {'pinned': activity['is_pinned'] != true},
      );
      await _loadActivities(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pin holatini o‘zgartirib bo‘lmadi: $error')),
      );
    }
  }

  Future<void> _showActivityActions(Map<String, dynamic> activity) async {
    final body = activity['body']?.toString().trim() ?? '';
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: const Text('Javob yozish'),
              onTap: () {
                Navigator.pop(sheetContext);
                _replyToActivity(activity);
              },
            ),
            ListTile(
              leading: Icon(
                activity['is_pinned'] == true
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                activity['is_pinned'] == true
                    ? 'Pindan chiqarish'
                    : 'Pin qilish',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _togglePin(activity);
              },
            ),
            if (body.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Matnni nusxalash'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: body));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(Map<String, dynamic> file) async {
    final id = (file['id'] as num?)?.toInt();
    if (id == null || _openingFileIds.contains(id)) return;
    setState(() => _openingFileIds.add(id));
    try {
      await widget.onDownloadAttachment(file);
    } finally {
      if (mounted) setState(() => _openingFileIds.remove(id));
    }
  }

  Future<void> _uploadActivityAttachment(PlatformFile file) async {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await widget.apiClient.multipartPost(
          '/task-kpi/tasks/${task['id']}/attachments',
          files: [
            await http.MultipartFile.fromPath(
              'file',
              path,
              filename: file.name,
            ),
          ],
        );
        return;
      } on FileSystemException {
        // Android content-provider paths can expire; use picker bytes below.
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fayl ma’lumotini o‘qib bo‘lmadi. Qayta tanlang.');
    }
    await widget.apiClient.multipartPost(
      '/task-kpi/tasks/${task['id']}/attachments',
      files: [http.MultipartFile.fromBytes('file', bytes, filename: file.name)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    final status = task['status'] as String? ?? 'todo';
    final description = task['description'] as String? ?? '';
    final permissions =
        (task['permissions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    // Workflow buttons belong only to the assigned employee. Managers and
    // task creators review/return the submitted work instead of starting it.
    final canAdvance = permissions['is_assignee'] == true;
    final canComment =
        permissions.isEmpty || permissions['can_comment'] == true;
    final actionLabel = switch (status) {
      'todo' when canAdvance => 'Qabul qildim',
      'accepted' when canAdvance => 'Ishni boshladim',
      'returned' when canAdvance => 'Qayta ishlashni boshlash',
      'in_progress' when canAdvance => 'Ishni topshirish',
      _ => null,
    };
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 0,
        titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        title: Text(
          task['title'] as String? ?? 'Vazifa',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.xs,
                spacing.sm,
                0,
              ),
              child: Wrap(
                spacing: spacing.xs,
                runSpacing: spacing.xs,
                children: [
                  _metaPill(context, _statusLabel(status), Icons.flag_outlined),
                  _metaPill(
                    context,
                    _priorityLabel(task['priority'] as String? ?? 'normal'),
                    Icons.bolt_outlined,
                  ),
                ],
              ),
            ),
            SizedBox(height: spacing.xs),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: EdgeInsets.symmetric(horizontal: spacing.sm),
              indicatorSize: TabBarIndicatorSize.label,
              tabs: [
                const Tab(text: 'Topshiriq'),
                Tab(text: 'Izohlar (${_commentActivities.length})'),
                Tab(text: 'Fayllar (${_fileEntries.length})'),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.sm,
                  spacing.xs,
                  spacing.sm,
                  spacing.sm,
                ),
                child: _tabController.index == 0
                    ? _taskSection(
                        description: description,
                        status: status,
                        actionLabel: actionLabel,
                      )
                    : _tabController.index == 1
                    ? _commentsSection()
                    : _filesSection(),
              ),
            ),
            if (_tabController.index == 1 && canComment)
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.sm,
                    0,
                    spacing.sm,
                    spacing.xs,
                  ),
                  child: _activityComposer(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _commentActivities =>
      _activities.where((activity) {
        if (activity['kind'] != 'comment') return false;
        final body = activity['body']?.toString().trim() ?? '';
        final hasAttachments =
            (activity['attachments'] as List?)?.isNotEmpty == true;
        return body.isNotEmpty || hasAttachments;
      }).toList();

  List<Map<String, dynamic>> get _fileEntries {
    final result = <Map<String, dynamic>>[];
    final ids = <int>{};
    for (final raw in (task['attachments'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);
      final id = (item['id'] as num?)?.toInt();
      if (id != null) ids.add(id);
      result.add(item);
    }
    for (final activity in _activities) {
      final author = activity['author_name']?.toString() ?? 'Tizim';
      final createdAt = activity['created_at']?.toString() ?? '';
      for (final raw in (activity['attachments'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);
        final id = (item['id'] as num?)?.toInt();
        if (id != null && !ids.add(id)) continue;
        item['author_name'] = author;
        item['activity_created_at'] = createdAt;
        result.add(item);
      }
    }
    result.sort((a, b) {
      final aDate = DateTime.tryParse(
        a['activity_created_at']?.toString() ??
            a['created_at']?.toString() ??
            '',
      );
      final bDate = DateTime.tryParse(
        b['activity_created_at']?.toString() ??
            b['created_at']?.toString() ??
            '',
      );
      return (bDate ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
        aDate ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
    });
    return result;
  }

  Widget _taskSection({
    required String description,
    required String status,
    required String? actionLabel,
  }) {
    final spacing = context.appSpacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (description.trim().isNotEmpty)
          AppSurfaceCard(
            padding: EdgeInsets.all(spacing.sm),
            child: Text(
              description,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        SizedBox(height: spacing.xs),
        _infoRow(
          context,
          'Bajaruvchi',
          task['assignee_name'] as String? ?? '—',
        ),
        if (task['due_at']?.toString().isNotEmpty == true)
          _infoRow(context, 'Deadline', _formatDate(task['due_at'] as String)),
        if (task['completion_note']?.toString().isNotEmpty == true)
          _infoRow(context, 'Xodim izohi', task['completion_note'] as String),
        if (task['review_note']?.toString().isNotEmpty == true)
          _infoRow(context, 'Rahbar izohi', task['review_note'] as String),
        if ((task['attachments'] as List?)?.isNotEmpty == true) ...[
          SizedBox(height: spacing.sm),
          Text(
            'Topshiriqqa biriktirilgan',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: spacing.xs),
          ...(task['attachments'] as List).whereType<Map>().map(
            (item) => _fileTile(Map<String, dynamic>.from(item)),
          ),
        ],
        SizedBox(height: spacing.sm),
        if (status == 'submitted' && widget.canReview) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await widget.onReview(true);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('Tugatildi deb qabul qilish'),
            ),
          ),
          SizedBox(height: spacing.xs),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await widget.onReview(false);
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Qayta ishlashga qaytarish'),
            ),
          ),
        ] else if (actionLabel != null)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () async {
                await widget.onAdvance();
                if (context.mounted) Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(actionLabel),
            ),
          ),
      ],
    );
  }

  Widget _commentsSection() {
    final comments = _commentActivities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Izohlar',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Yangilash',
              onPressed: _loadingActivities ? null : _loadActivities,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (_pinnedActivities.isNotEmpty) ...[
          SizedBox(height: context.appSpacing.xs),
          _pinnedActivityBar(),
        ],
        if (_loadingActivities)
          const LinearProgressIndicator(minHeight: 2)
        else if (_activityError != null)
          AppStatusBanner(
            message: _activityError!,
            tone: AppStatusTone.danger,
            action: TextButton(
              onPressed: _loadActivities,
              child: const Text('Qayta urinish'),
            ),
          )
        else if (comments.isEmpty)
          Text(
            'Hozircha izoh yo‘q.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ChatThreadWidget(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            messages: comments.map(_toTaskThreadMessage).toList(),
            currentUserId: widget.currentUserId,
            isGroup: true,
            showSenderName: false,
            attachmentBuilder:
                (
                  context,
                  attachment, {
                  required message,
                  required showDeliveryOverlay,
                }) => _taskThreadAttachment(attachment),
            footerBuilder: (context, message) => _taskThreadFooter(message),
            onLongPressMessage: (message) async {
              final activity = message.raw as Map<String, dynamic>;
              await _showActivityActions(activity);
            },
            onLongPressAttachment: (attachment) async {
              final raw = attachment.raw as Map<String, dynamic>;
              _replyToAttachment(raw);
            },
            onTapReply: (message) async {
              if (message.replyKind == 'file' && message.replyId != null) {
                await _openAttachment({
                  'id': message.replyId,
                  'filename': message.replyLabel ?? 'Fayl',
                });
              }
            },
          ),
      ],
    );
  }

  ChatThreadMessage _toTaskThreadMessage(Map<String, dynamic> activity) {
    var body = activity['body']?.toString() ?? '';
    final authorId = _activityAuthorId(activity);
    final metadata = (activity['metadata'] as Map?)?.cast<String, dynamic>();
    var replyLabel =
        metadata?['reply_to_filename']?.toString() ??
        metadata?['reply_to_text']?.toString();
    var replyKind = metadata?['reply_to_attachment_id'] != null
        ? 'file'
        : metadata?['reply_to_activity_id'] != null
        ? 'comment'
        : null;
    var replyId =
        (metadata?['reply_to_attachment_id'] as num?)?.toInt() ??
        (metadata?['reply_to_activity_id'] as num?)?.toInt();
    final firstLine = body.split('\n').first.trim();
    final marker = RegExp(
      r'^(Faylga|Izohga) javob: (.+?) \[(file|comment):(\d+)\]$',
    ).firstMatch(firstLine);
    if (marker != null) {
      replyKind ??= marker.group(3);
      replyId ??= int.tryParse(marker.group(4)!);
      replyLabel ??= marker.group(2)?.trim();
      body = body.substring(firstLine.length).trim();
    }
    final rawAttachments = (activity['attachments'] as List?) ?? const [];
    return ChatThreadMessage(
      id: (activity['id'] as num?)?.toInt() ?? 0,
      senderId: authorId,
      senderName: activity['author_name']?.toString() ?? 'Tizim',
      body: body.startsWith('Fayl biriktirdi:') ? '' : body,
      createdAt:
          DateTime.tryParse(activity['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isMine: authorId == widget.currentUserId,
      isPinned: activity['is_pinned'] == true,
      replyLabel: replyLabel,
      replyKind: replyKind,
      replyId: replyId,
      attachments: rawAttachments.whereType<Map>().map((raw) {
        return ChatThreadAttachment(
          id: (raw['id'] as num?)?.toInt() ?? 0,
          filename: raw['filename']?.toString() ?? 'Fayl',
          mimeType: _mimeType(raw['filename']?.toString() ?? ''),
          sizeBytes: (raw['size_bytes'] as num?)?.toInt() ?? 0,
          raw: Map<String, dynamic>.from(raw),
        );
      }).toList(),
      raw: activity,
    );
  }

  int _activityAuthorId(Map<String, dynamic> activity) {
    for (final key in const [
      'author_id',
      'created_by_id',
      'user_id',
      'actor_id',
    ]) {
      final value = activity[key];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed > 0) return parsed;
    }
    final author = activity['author'];
    if (author is Map) {
      final value = author['id'];
      final parsed = value is num ? value.toInt() : int.tryParse('$value');
      if (parsed != null && parsed > 0) return parsed;
    }
    return 0;
  }

  Widget _taskThreadAttachment(ChatThreadAttachment attachment) {
    final raw = attachment.raw as Map<String, dynamic>;
    final isImage = attachment.mimeType.startsWith('image/');
    return ActionChip(
      avatar: Icon(
        isImage ? Icons.image_outlined : Icons.attach_file_rounded,
        size: 17,
      ),
      label: Text(
        '${attachment.filename} (${_formatBytes(attachment.sizeBytes)})',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: () => _openAttachment(raw),
    );
  }

  Widget _taskThreadFooter(ChatThreadMessage message) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatDate(message.createdAt.toIso8601String()),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: message.isMine
                ? Colors.white.withValues(alpha: 0.72)
                : context.appColors.textMuted,
          ),
        ),
        if (message.isPinned) ...[
          SizedBox(width: context.appSpacing.xs),
          Icon(
            Icons.push_pin_rounded,
            size: 14,
            color: message.isMine ? Colors.white : context.appColors.primary,
          ),
        ],
      ],
    );
  }

  Widget _pinnedActivityBar() {
    final pinned = _pinnedActivities.first;
    final preview = pinned['body']?.toString().split('\n').last.trim() ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(context.appRadii.md),
      onTap: () => _showActivityActions(pinned),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.sm,
          vertical: context.appSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.appColors.surfaceMuted,
          borderRadius: BorderRadius.circular(context.appRadii.md),
          border: Border.all(color: context.appColors.border),
        ),
        child: Row(
          children: [
            Icon(
              Icons.push_pin_rounded,
              size: 17,
              color: context.appColors.primary,
            ),
            SizedBox(width: context.appSpacing.xs),
            Expanded(
              child: Text(
                preview.isEmpty ? 'Biriktirilgan xabar' : preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _filesSection() {
    final spacing = context.appSpacing;
    final files = _fileEntries;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Vazifa fayllari',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Yangilash',
              onPressed: _loadingActivities ? null : _loadActivities,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (_loadingActivities)
          const LinearProgressIndicator(minHeight: 2)
        else if (files.isEmpty)
          Text(
            'Hozircha fayl yo‘q.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else
          ...files.map(_fileTile),
        SizedBox(height: spacing.xs),
        Text(
          'Fayllar vaqt bo‘yicha alohida saqlanadi; ularni vazifa ichidan ochish yoki yuklab olish mumkin.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.appColors.textMuted),
        ),
      ],
    );
  }

  Widget _fileTile(Map<String, dynamic> file) {
    final spacing = context.appSpacing;
    final filename = file['filename'] as String? ?? 'Fayl';
    final mime = _mimeType(filename);
    final isImage = mime.startsWith('image/');
    final id = (file['id'] as num?)?.toInt();
    final isOpening = id != null && _openingFileIds.contains(id);
    final author = file['author_name']?.toString();
    final date =
        file['activity_created_at']?.toString() ??
        file['created_at']?.toString() ??
        '';
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: AppSurfaceCard(
        padding: EdgeInsets.symmetric(horizontal: spacing.xs, vertical: 2),
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: spacing.xs),
          leading: Icon(
            isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
          ),
          title: Text(filename, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            isOpening
                ? 'Yuklanmoqda…'
                : [
                    _formatBytes(file['size_bytes'] as int? ?? 0),
                    if (author?.isNotEmpty == true) author!,
                    if (date.isNotEmpty) _formatDate(date),
                  ].join(' • '),
          ),
          trailing: isOpening
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.open_in_new_rounded, size: 19),
          onTap: isOpening ? null : () => _openAttachment(file),
          onLongPress: isOpening ? null : () => _replyToAttachment(file),
        ),
      ),
    );
  }

  Widget _metaPill(BuildContext context, String label, IconData icon) {
    final colors = context.appColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(context.appRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.textMuted),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }

  // Legacy renderer retained for compatibility with old hot-reload sessions.
  // ignore: unused_element
  Widget _activityTile(Map<String, dynamic> activity) {
    final spacing = context.appSpacing;
    var body = activity['body'] as String? ?? '';
    final author = activity['author_name'] as String? ?? 'Tizim';
    final createdAt = activity['created_at']?.toString() ?? '';
    final metadata = (activity['metadata'] as Map?)?.cast<String, dynamic>();
    var replyLabel =
        metadata?['reply_to_filename']?.toString() ??
        metadata?['reply_to_text']?.toString();
    var replyKind = metadata?['reply_to_attachment_id'] != null
        ? 'file'
        : metadata?['reply_to_activity_id'] != null
        ? 'comment'
        : null;
    var replyId =
        (metadata?['reply_to_attachment_id'] as num?)?.toInt() ??
        (metadata?['reply_to_activity_id'] as num?)?.toInt();
    final firstLine = body.split('\n').first.trim();
    final marker = RegExp(
      r'^(Faylga|Izohga) javob: (.+?) \[(file|comment):(\d+)\]$',
    ).firstMatch(firstLine);
    if (marker != null) {
      replyKind ??= marker.group(3);
      replyId ??= int.tryParse(marker.group(4)!);
      replyLabel ??= marker.group(2)?.trim();
      body = body.substring(firstLine.length).trim();
    } else if (firstLine.startsWith('Faylga javob: ')) {
      replyKind ??= 'file';
      replyLabel ??= firstLine.substring('Faylga javob: '.length).trim();
      body = body.substring(firstLine.length).trim();
    } else if (firstLine.startsWith('Izohga javob: ')) {
      replyKind ??= 'comment';
      replyLabel ??= firstLine.substring('Izohga javob: '.length).trim();
      body = body.substring(firstLine.length).trim();
    }
    final isMine =
        (activity['author_id'] as num?)?.toInt() == widget.currentUserId;
    return Padding(
      padding: EdgeInsets.only(bottom: spacing.xs),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.84,
          ),
          child: GestureDetector(
            onLongPress: () => _showActivityActions(activity),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: spacing.sm,
                vertical: spacing.xs,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? context.appColors.chatMine
                    : context.appColors.surface,
                borderRadius: BorderRadius.circular(context.appRadii.lg),
                border: Border.all(
                  color: isMine
                      ? context.appColors.primary.withValues(alpha: 0.12)
                      : context.appColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          author,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isMine ? Colors.white : null,
                              ),
                        ),
                      ),
                      if (activity['is_pinned'] == true)
                        Icon(
                          Icons.push_pin_rounded,
                          size: 15,
                          color: isMine
                              ? Colors.white
                              : context.appColors.primary,
                        ),
                    ],
                  ),
                  if (replyLabel?.isNotEmpty == true) ...[
                    SizedBox(height: spacing.xs),
                    InkWell(
                      borderRadius: BorderRadius.circular(context.appRadii.sm),
                      onTap: replyKind == 'file' && replyId != null
                          ? () => _openAttachment({
                              'id': replyId,
                              'filename': replyLabel,
                            })
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: spacing.xs,
                          vertical: spacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Colors.white.withValues(alpha: 0.14)
                              : context.appColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(
                            context.appRadii.sm,
                          ),
                          border: Border(
                            left: BorderSide(
                              color: isMine
                                  ? Colors.white.withValues(alpha: 0.8)
                                  : context.appColors.primary,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              replyKind == 'file'
                                  ? Icons.attach_file_rounded
                                  : Icons.reply_rounded,
                              size: 16,
                              color: isMine ? Colors.white : null,
                            ),
                            SizedBox(width: spacing.xs),
                            Expanded(
                              child: Text(
                                'Javob: $replyLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: isMine ? Colors.white : null,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (body.trim().isNotEmpty) ...[
                    SizedBox(height: spacing.xs),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isMine ? Colors.white : null,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      createdAt.isEmpty ? '' : _formatDate(createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.72)
                            : context.appColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _activityComposer() {
    final spacing = context.appSpacing;
    return Container(
      decoration: BoxDecoration(
        color: context.appColors.surface,
        borderRadius: BorderRadius.circular(context.appRadii.lg),
        border: Border.all(color: context.appColors.border),
      ),
      padding: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.xs,
        spacing.xs,
        spacing.xs,
      ),
      child: Column(
        children: [
          if (_replyTarget != null)
            Container(
              width: double.infinity,
              margin: EdgeInsets.only(bottom: spacing.xs),
              padding: EdgeInsets.symmetric(
                horizontal: spacing.xs,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: context.appColors.surfaceMuted,
                borderRadius: BorderRadius.circular(context.appRadii.sm),
                border: Border(
                  left: BorderSide(color: context.appColors.primary, width: 3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, size: 17),
                  SizedBox(width: spacing.xs),
                  Expanded(
                    child: Text(
                      '${_replyTarget!['kind'] == 'file' ? 'Faylga' : 'Izohga'} javob: ${_replyTarget!['label'] ?? 'Tanlangan matn'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _sendingUpdate
                        ? null
                        : () => setState(() => _replyTarget = null),
                    icon: const Icon(Icons.close_rounded, size: 17),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !_sendingUpdate,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Izoh yozing…',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Rasm yoki fayl biriktirish',
                onPressed: _sendingUpdate ? null : _pickActivityAttachments,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              IconButton.filled(
                tooltip: 'Yuborish',
                onPressed: _sendingUpdate ? null : _sendUpdate,
                icon: _sendingUpdate
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.arrow_upward_rounded, size: 18),
              ),
            ],
          ),
          if (_selectedAttachments.isNotEmpty)
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedAttachments.length,
                separatorBuilder: (_, _) => SizedBox(width: spacing.xs),
                itemBuilder: (context, index) {
                  final file = _selectedAttachments[index];
                  return InputChip(
                    label: Text(
                      file.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: _sendingUpdate
                        ? null
                        : () => setState(() {
                            _selectedAttachments = [
                              ..._selectedAttachments.sublist(0, index),
                              ..._selectedAttachments.sublist(index + 1),
                            ];
                          }),
                  );
                },
              ),
            ),
        ],
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

  String _mimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
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
  static const _maxAttachmentBytes = 25 * 1024 * 1024;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  int? _assigneeId;
  String _priority = 'normal';
  DateTime? _dueAt;
  List<PlatformFile> _attachments = const [];
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
    final oversized = _attachments.where(
      (file) => file.size > _maxAttachmentBytes,
    );
    if (oversized.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${oversized.first.name} hajmi 25 MB dan oshmasligi kerak.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final created = await widget.apiClient.post('/task-kpi/tasks', {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'assignee_id': _assigneeId,
        'priority': _priority,
        if (_dueAt != null) 'due_at': _dueAt!.toUtc().toIso8601String(),
      });
      if (_attachments.isNotEmpty && created is Map && created['id'] != null) {
        final taskId = (created['id'] as num).toInt();
        for (final attachment in _attachments) {
          await _uploadAttachment(taskId, attachment);
        }
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

  Future<void> _uploadAttachment(int taskId, PlatformFile file) async {
    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      try {
        await widget.apiClient.multipartPost(
          '/task-kpi/tasks/$taskId/attachments',
          files: [
            await http.MultipartFile.fromPath(
              'file',
              path,
              filename: file.name,
            ),
          ],
        );
        return;
      } on FileSystemException {
        // Android content providers can expose a temporary path that is no
        // longer readable by the time the multipart stream starts. In that
        // case use the bytes loaded by FilePicker instead.
      }
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fayl ma’lumotini o‘qib bo‘lmadi. Qayta tanlang.');
    }
    await widget.apiClient.multipartPost(
      '/task-kpi/tasks/$taskId/attachments',
      files: [http.MultipartFile.fromBytes('file', bytes, filename: file.name)],
    );
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
                itemHeight: null,
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
                    allowMultiple: true,
                    withData: true,
                  );
                  if (result != null && result.files.isNotEmpty) {
                    final selected = result.files.where(
                      (file) => file.size > 0,
                    );
                    final existing = _attachments
                        .map((file) => '${file.name}:${file.size}')
                        .toSet();
                    final added = selected
                        .where(
                          (file) => existing.add('${file.name}:${file.size}'),
                        )
                        .toList();
                    if (added.isNotEmpty) {
                      setState(
                        () => _attachments = [..._attachments, ...added],
                      );
                    }
                  }
                },
                icon: const Icon(Icons.attach_file_rounded),
                label: Text(
                  _attachments.isEmpty
                      ? 'Fayllar biriktirish (ixtiyoriy)'
                      : '${_attachments.length} ta fayl tanlangan',
                ),
              ),
              if (_attachments.isNotEmpty) ...[
                SizedBox(height: spacing.xs),
                ..._attachments.asMap().entries.map(
                  (entry) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      entry.value.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(_formatBytes(entry.value.size)),
                    trailing: IconButton(
                      tooltip: 'Olib tashlash',
                      onPressed: _saving
                          ? null
                          : () => setState(
                              () => _attachments = [
                                ..._attachments.sublist(0, entry.key),
                                ..._attachments.sublist(entry.key + 1),
                              ],
                            ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
                ),
              ],
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
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
  // Completed work stays out of the main inbox; it remains available through
  // the explicit "Tugallangan" filter.
  String _statusFilter = 'open';
  Timer? _searchDebounce;
  Timer? _refreshTimer;
  bool _loadInFlight = false;

  List<Map<String, dynamic>> get _visibleTasks {
    final query = _searchController.text.trim().toLowerCase();
    return _tasks.where((task) {
      final status = task['status'] as String? ?? 'todo';
      final title = (task['title'] as String? ?? '').toLowerCase();
      final description = (task['description'] as String? ?? '').toLowerCase();
      final matchesStatus = _statusFilter == 'open'
          ? status != 'done'
          : _statusFilter == 'all' || status == _statusFilter;
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
      if (mounted) unawaited(_load(background: true));
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

  Future<void> _load({bool append = false, bool background = false}) async {
    if (append && (_loadingMore || !_hasMore || _nextOffset == null)) return;
    if (_loadInFlight) return;
    _loadInFlight = true;
    if (mounted && !background) {
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
    }
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
        if (!background) _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    } finally {
      _loadInFlight = false;
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
      final root = await getApplicationDocumentsDirectory();
      final directory = Directory(p.join(root.path, 'task-kpi'));
      await directory.create(recursive: true);
      final rawName = attachment['filename'] as String? ?? 'attachment';
      final safeName = rawName.replaceAll(RegExp(r'[\\/]'), '_');
      final file = File(p.join(directory.path, '${id}_$safeName'));
      if (!await file.exists() || await file.length() == 0) {
        final response = await widget.apiClient
            .getBytes('/task-kpi/attachments/$id/download')
            .timeout(const Duration(seconds: 45));
        await file.writeAsBytes(response.bytes, flush: true);
      }
      final mime = _attachmentMimeType(rawName);
      if (mime.startsWith('image/')) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => Dialog(
            insetPadding: const EdgeInsets.all(12),
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.file(file, fit: BoxFit.contain),
            ),
          ),
        );
      } else {
        await OpenFilex.open(file.path, type: mime);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Faylni yuklab bo‘lmadi: $error')));
    }
  }

  String _attachmentMimeType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    return 'application/octet-stream';
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
          apiClient: widget.apiClient,
          currentUserId: widget.currentUserId,
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
                      withData: true,
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
