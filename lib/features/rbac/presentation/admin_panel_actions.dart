part of 'admin_panel_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _AdminPanelActions on _AdminPanelPageState {
  List<Map<String, dynamic>> get _filteredMembers {
    final query = _memberSearchController.text.trim().toLowerCase();
    final filtered = _members.where((member) {
      final isActive = member['is_active'] == true;
      if (_memberStatusFilter == 'active' && !isActive) return false;
      if (_memberStatusFilter == 'inactive' && isActive) return false;
      final role = member['role'] as Map<String, dynamic>?;
      if (_memberStatusFilter == 'unassigned' && role?['id'] != null) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        member['display_name'],
        member['email'],
        role?['name'],
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
    filtered.sort((a, b) {
      final aRole = a['role'] as Map<String, dynamic>?;
      final bRole = b['role'] as Map<String, dynamic>?;
      final aUnassigned = aRole?['id'] == null;
      final bUnassigned = bRole?['id'] == null;
      if (aUnassigned != bUnassigned) return aUnassigned ? -1 : 1;
      final aName = (a['display_name'] as String? ?? '').toLowerCase();
      final bName = (b['display_name'] as String? ?? '').toLowerCase();
      return aName.compareTo(bName);
    });
    return filtered;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        widget.repository.get('/rbac/me'),
        widget.repository.get('/rbac/roles'),
        widget.repository.get('/rbac/members'),
      ]);
      if (!mounted) return;
      setState(() {
        _isAdmin = (results[0] as Map<String, dynamic>)['is_admin'] == true;
        _roles = List<Map<String, dynamic>>.from(results[1] as List);
        _members = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
      _refreshRegisteredUserCount();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshRegisteredUserCount() async {
    if (!_isAdmin) return;
    try {
      final users = await widget.repository.get('/rbac/registered-users');
      if (mounted && users is List) {
        final ids = users
            .whereType<Map>()
            .map((user) => user['user_id'])
            .whereType<num>()
            .map((id) => id.toInt())
            .toSet();
        setState(() => _registeredUserCount = ids.length);
      }
    } catch (_) {
      if (mounted) setState(() => _registeredUserCount = 0);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}
