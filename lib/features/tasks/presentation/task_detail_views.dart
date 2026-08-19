part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskDetailViews on _TaskDetailPageState {
  Widget _buildPage(BuildContext context) {
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
                Tab(text: 'Faoliyat (${_commentActivities.length})'),
                const Tab(text: 'Vazifa chati'),
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
                    : _tabController.index == 2
                    ? _kpiChatSection()
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

  Widget _kpiChatSection() {
    final spacing = context.appSpacing;
    final colors = context.appColors;
    return AppSurfaceCard(
      backgroundColor: colors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.forum_rounded, color: colors.primary, size: 28),
          SizedBox(height: spacing.sm),
          Text(
            'Vazifa ishchi chati',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Bu suhbat faqat shu topshiriqqa tegishli. U oddiy private chat tarixidan alohida saqlanadi, lekin asosiy app chatining shifrlash, outbox va qayta yuborish mexanizmlaridan foydalanadi.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SizedBox(height: spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _openTaskChat,
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Vazifa chatini ochish'),
            ),
          ),
        ],
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
                if (!mounted) return;
                Navigator.pop(context);
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
                if (!mounted) return;
                Navigator.pop(context);
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
                if (!mounted) return;
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Text(actionLabel),
            ),
          ),
      ],
    );
  }
}
