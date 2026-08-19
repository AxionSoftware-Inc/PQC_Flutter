class ApiConfig {
  static const _debugFallback = 'http://169.58.123.200/api';
  static const _isProductBuild = bool.fromEnvironment('dart.vm.product');

  static String get baseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    final candidate = defined.trim().isEmpty ? _debugFallback : defined.trim();
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw StateError(
        'API_BASE_URL must be an absolute http(s) URL without query or fragment.',
      );
    }
    if (_isProductBuild && uri.scheme != 'https') {
      throw StateError(
        'Release builds require an HTTPS API_BASE_URL. '
        'Pass --dart-define=API_BASE_URL=https://... .',
      );
    }
    return candidate;
  }
}
