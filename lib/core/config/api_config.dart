class ApiConfig {
  static const _defaultBase = 'http://91.108.121.56/api';

  static String get baseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    return _defaultBase;
  }
}
