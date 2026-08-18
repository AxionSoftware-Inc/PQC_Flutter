part of 'task_kpi_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _TaskKpiDataActions on _TaskKpiPageState {
  Future<dynamic> _optionalGet(String path) async {
    try {
      return await widget.repository.get(path);
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
              widget.repository.get('/task-kpi/tasks', queryParameters: query),
            ])
          : await Future.wait<dynamic>([
              widget.repository.get('/task-kpi/tasks', queryParameters: query),
              widget.repository.get('/task-kpi/assignees'),
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
}
