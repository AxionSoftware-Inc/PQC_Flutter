class ApiConfig {
  // The default points at the current deployment. Production/release builds
  // should still pass API_BASE_URL explicitly, so moving servers never
  // requires changing crypto or UI code.
  static const _productionBase = 'http://169.58.123.200/api';

  static String get baseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    return _productionBase;
  }
}
