import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.isRetryable = false,
  });

  final String message;
  final int? statusCode;
  final String? code;
  final bool isRetryable;

  @override
  String toString() => message;
}

class UnauthorizedApiException extends ApiException {
  UnauthorizedApiException([
    super.message = 'Invalid token. Please log in again.',
  ]) : super(statusCode: 401, code: 'not_authenticated');
}

class ApiClient {
  final http.Client _client = http.Client();
  String? _token;
  String? _deviceId;
  String? _workspaceId;

  void setToken(String? token) {
    _token = token;
  }

  void setDeviceId(String? deviceId) {
    _deviceId = deviceId;
  }

  void setWorkspaceId(String? workspaceId) {
    _workspaceId = workspaceId;
  }

  String websocketUrl(String path, {Map<String, String>? queryParameters}) {
    final uri = _buildUri(path, queryParameters: queryParameters);
    return uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws').toString();
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final response = await _send(
      () => _client.get(
        _buildUri(path, queryParameters: queryParameters),
        headers: _headers(),
      ),
    );
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await _send(
      () => _client.post(
        _buildUri(path),
        headers: _headers(),
        body: jsonEncode(body),
      ),
    );
    return _decode(response);
  }

  Future<dynamic> multipartPost(
    String path, {
    required List<http.MultipartFile> files,
    Map<String, String>? fields,
  }) async {
    final request = http.MultipartRequest('POST', _buildUri(path));
    request.headers.addAll(_headers()..remove('Content-Type'));
    if (fields != null) {
      request.fields.addAll(fields);
    }
    request.files.addAll(files);
    final response = await _send(() async {
      final streamed = await request.send();
      return http.Response.fromStream(streamed);
    });
    return _decode(response);
  }

  Uri _buildUri(String path, {Map<String, String>? queryParameters}) {
    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final base = Uri.parse('$normalizedBase$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) {
      return base;
    }
    return base.replace(
      queryParameters: {...base.queryParameters, ...queryParameters},
    );
  }

  Map<String, String> _headers() {
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Token $_token',
      if (_deviceId != null && _deviceId!.isNotEmpty) 'X-Device-Id': _deviceId!,
      if (_workspaceId != null && _workspaceId!.isNotEmpty)
        'X-Workspace-Id': _workspaceId!,
    };
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request();
    } on SocketException {
      throw ApiException(
        'Network unavailable. Please try again.',
        code: 'network_unavailable',
        isRetryable: true,
      );
    } on HttpException {
      throw ApiException(
        'Server connection failed.',
        code: 'connection_failed',
        isRetryable: true,
      );
    }
  }

  dynamic _decode(http.Response response) {
    dynamic decoded;
    final responseText = utf8.decode(response.bodyBytes);
    if (responseText.isNotEmpty) {
      try {
        decoded = jsonDecode(responseText);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw ApiException(
            'Server returned an unexpected response.',
            statusCode: response.statusCode,
            code: 'unexpected_response',
          );
        }

        throw ApiException(
          'Server returned an unexpected non-JSON error '
          '(${response.statusCode}): ${_responseSnippet(responseText)}',
          statusCode: response.statusCode,
          code: 'non_json_error',
          isRetryable: response.statusCode >= 500,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401) {
      throw UnauthorizedApiException();
    }
    if (response.statusCode == 413) {
      throw ApiException(
        'File is too large for the server upload limit.',
        statusCode: response.statusCode,
        code: 'payload_too_large',
      );
    }

    final message = decoded is Map<String, dynamic>
        ? (decoded['detail'] as String?) ?? 'Request failed.'
        : 'Request failed.';
    final code = decoded is Map<String, dynamic>
        ? decoded['code'] as String?
        : null;
    throw ApiException(
      message,
      statusCode: response.statusCode,
      code: code,
      isRetryable: response.statusCode >= 500 || response.statusCode == 429,
    );
  }

  String _responseSnippet(String value) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 240) return normalized;
    return '${normalized.substring(0, 240)}…';
  }
}
