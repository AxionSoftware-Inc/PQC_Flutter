import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:crypto_core/crypto_core.dart';

import '../../../core/network/api_client.dart';

/// Feature boundary for task-center HTTP operations.
///
/// KPI goals and scoring remain backend-owned contracts for the future
/// standalone KPI app; this client currently consumes task workflow and
/// operational reporting only.
///
/// Presentation code depends on this contract instead of the shared transport
/// client. Endpoint details and multipart construction stay in the data layer.
class TaskKpiRepository {
  const TaskKpiRepository._(this._apiClient);

  factory TaskKpiRepository({required ApiClient apiClient}) =>
      TaskKpiRepository._(apiClient);

  final ApiClient _apiClient;

  Future<dynamic> listTasks({
    required int offset,
    required int limit,
    String? status,
    String? query,
  }) {
    return _apiClient.get(
      '/task-kpi/tasks',
      queryParameters: {
        'offset': '$offset',
        'limit': '$limit',
        if (status != null && status.isNotEmpty) 'status': status,
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      },
    );
  }

  Future<dynamic> listAssignees() => _apiClient.get('/task-kpi/assignees');

  Future<dynamic> getNotifications() =>
      _apiClient.get('/task-kpi/notifications');

  Future<dynamic> getKpiSummary() => _apiClient.get('/task-kpi/kpi-summary');

  Future<dynamic> getDashboard() => _apiClient.get('/task-kpi/dashboard');

  Future<dynamic> getReport() => _apiClient.get('/task-kpi/reports');

  Future<dynamic> createTask({
    required String title,
    required String description,
    required int assigneeId,
    required String priority,
    DateTime? dueAt,
  }) {
    return _apiClient.post('/task-kpi/tasks', {
      'title': title,
      'description': description,
      'assignee_id': assigneeId,
      'priority': priority,
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
    });
  }

  Future<dynamic> updateTask(int taskId, Map<String, dynamic> body) {
    return _apiClient.patch('/task-kpi/tasks/$taskId', body);
  }

  Future<dynamic> getTaskActivity(int taskId) {
    return _apiClient.get('/task-kpi/tasks/$taskId/activity');
  }

  Future<dynamic> addTaskActivity(int taskId, Map<String, dynamic> body) {
    return _apiClient.post('/task-kpi/tasks/$taskId/activity', body);
  }

  Future<dynamic> pinTaskActivity(
    int taskId,
    int activityId, {
    required bool pinned,
  }) {
    return _apiClient.post('/task-kpi/tasks/$taskId/activity/$activityId/pin', {
      'pinned': pinned,
    });
  }

  Future<void> markNotificationsRead() async {
    await _apiClient.post('/task-kpi/notifications/read', const {});
  }

  Future<Conversation> openTaskConversation(int taskId) async {
    final response = await _apiClient.post(
      '/task-kpi/tasks/$taskId/conversation',
      const {},
    );
    if (response is! Map<String, dynamic>) {
      throw StateError('KPI conversation response is invalid.');
    }
    return Conversation.fromJson(response);
  }

  Future<dynamic> uploadTaskAttachment(
    int taskId, {
    String? path,
    List<int>? bytes,
    required String filename,
  }) async {
    final normalizedPath = path?.trim();
    if (normalizedPath != null && normalizedPath.isNotEmpty) {
      try {
        return await _apiClient.multipartPost(
          '/task-kpi/tasks/$taskId/attachments',
          files: [
            await http.MultipartFile.fromPath(
              'file',
              normalizedPath,
              filename: filename,
            ),
          ],
        );
      } on FileSystemException {
        // Android content-provider paths can expire; use picker bytes below.
      }
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Fayl ma’lumotini o‘qib bo‘lmadi. Qayta tanlang.');
    }
    return _apiClient.multipartPost(
      '/task-kpi/tasks/$taskId/attachments',
      files: [http.MultipartFile.fromBytes('file', bytes, filename: filename)],
    );
  }

  Future<ApiBinaryResponse> downloadTaskAttachment(int attachmentId) =>
      _apiClient.getBytes('/task-kpi/attachments/$attachmentId/download');
}
