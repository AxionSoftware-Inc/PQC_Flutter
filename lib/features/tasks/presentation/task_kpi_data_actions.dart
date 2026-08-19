part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskKpiDataActions on _TaskKpiPageState {
  Future<dynamic> _optional(Future<dynamic> Function() request) async {
    try {
      return await request();
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
      final offset = append ? _nextOffset ?? 0 : 0;
      final search = _searchController.text.trim();
      final values = append
          ? await Future.wait<dynamic>([
              widget.repository.listTasks(
                offset: offset,
                limit: 50,
                status: _statusFilter == 'all' ? null : _statusFilter,
                query: search,
              ),
            ])
          : await Future.wait<dynamic>([
              widget.repository.listTasks(
                offset: offset,
                limit: 50,
                status: _statusFilter == 'all' ? null : _statusFilter,
                query: search,
              ),
              widget.repository.listAssignees(),
              _optional(widget.repository.getNotifications),
              _optional(widget.repository.getKpiSummary),
              _optional(widget.repository.getDashboard),
              _optional(widget.repository.getReport),
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
          _dashboard = values[4] is Map
              ? Map<String, dynamic>.from(values[4] as Map)
              : const {};
          _report = values[5] is Map
              ? Map<String, dynamic>.from(values[5] as Map)
              : const {};
          _dashboardLoading = false;
        }
        _hasMore = taskPage['has_more'] == true;
        _nextOffset = taskPage['next_offset'] as int?;
        _loading = false;
        _loadingMore = false;
        if (!append) _dashboardLoading = false;
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
}
