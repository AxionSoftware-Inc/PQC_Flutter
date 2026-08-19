import 'package:http/http.dart' as http;
import 'package:crypto_core/crypto_core.dart';

import '../../../core/network/api_client.dart';

/// Feature boundary for task/KPI HTTP operations.
///
/// Presentation code depends on this contract instead of the shared transport
/// client. Endpoint details stay in the task data layer until typed DTOs are
/// introduced.
class TaskKpiRepository {
  const TaskKpiRepository._(this._apiClient);

  factory TaskKpiRepository({required ApiClient apiClient}) =>
      TaskKpiRepository._(apiClient);

  final ApiClient _apiClient;

  Future<dynamic> get(String path, {Map<String, String>? queryParameters}) {
    return _apiClient.get(path, queryParameters: queryParameters);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) {
    return _apiClient.post(path, body);
  }

  Future<dynamic> patch(String path, Map<String, dynamic> body) {
    return _apiClient.patch(path, body);
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

  Future<dynamic> multipartPost(
    String path, {
    required List<http.MultipartFile> files,
    Map<String, String>? fields,
  }) {
    return _apiClient.multipartPost(path, files: files, fields: fields);
  }

  Future<ApiBinaryResponse> getBytes(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return _apiClient.getBytes(path, queryParameters: queryParameters);
  }
}
