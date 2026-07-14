class ApiConfig {
  static const googleWebClientId =
      '937305477350-n9h2s4e6ra9rvs6s1s95gel6p4ldl5tg.apps.googleusercontent.com';

  static const _productionBase = 'http://91.108.121.56/api';

  static String get baseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    return _productionBase;
  }
}
