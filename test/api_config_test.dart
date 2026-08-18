import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/config/api_config.dart';

void main() {
  test('settings and network clients share the production API default', () {
    expect(ApiConfig.baseUrl, 'http://169.58.123.200/api');
  });
}
