import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UnauthorizedApiException extends ApiException {
  UnauthorizedApiException([
    super.message = 'Invalid token. Please log in again.',
  ]);
}

class ApiClient {
  final http.Client _client = http.Client();
  String? _token;
  String? _deviceId;

  void setToken(String? token) {
    _token = token;
  }

  void setDeviceId(String? deviceId) {
    _deviceId = deviceId;
  }

  Future<dynamic> get(String path) async {
    final response = await _client.get(_buildUri(path), headers: _headers());
    return _decode(response);
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final response = await _client.post(
      _buildUri(path),
      headers: _headers(),
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Uri _buildUri(String path) {
    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  Map<String, String> _headers() {
    return {
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Token $_token',
      if (_deviceId != null && _deviceId!.isNotEmpty) 'X-Device-Id': _deviceId!,
    };
  }

  dynamic _decode(http.Response response) {
    dynamic decoded;
    final responseText = utf8.decode(response.bodyBytes);
    if (responseText.isNotEmpty) {
      try {
        decoded = jsonDecode(responseText);
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw ApiException('Server returned an unexpected response.');
        }

        throw ApiException(
          'Server returned an unexpected non-JSON error '
          '(${response.statusCode}).',
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    if (response.statusCode == 401) {
      throw UnauthorizedApiException();
    }

    final message = decoded is Map<String, dynamic>
        ? (decoded['detail'] as String?) ?? 'Request failed.'
        : 'Request failed.';
    throw ApiException(message);
  }
}
