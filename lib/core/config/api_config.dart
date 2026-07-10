import 'dart:io';

import 'package:flutter/foundation.dart';

class ApiConfig {
  static const _productionBase = 'http://91.108.121.56/api';
  static const _desktopDebugBase = 'http://127.0.0.1:8000/api';
  static const _androidEmulatorDebugBase = 'http://10.0.2.2:8000/api';

  static String get baseUrl {
    const fromDefine = String.fromEnvironment('API_BASE_URL');
    if (fromDefine.isNotEmpty) {
      return fromDefine;
    }

    if (!kIsWeb && kDebugMode) {
      if (Platform.isAndroid) {
        return _androidEmulatorDebugBase;
      }
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        return _desktopDebugBase;
      }
      if (Platform.isIOS) {
        return _desktopDebugBase;
      }
    }

    return _productionBase;
  }
}
