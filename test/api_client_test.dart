import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';

void main() {
  test('unauthorized exception carries session-expired meaning', () {
    final error = UnauthorizedApiException();

    expect(error.toString(), 'Invalid token. Please log in again.');
  });
}
