class ApiConfig {
  static const _productionBase = 'http://169.58.123.200/api';

  static String get baseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    return _productionBase;
  }
}
