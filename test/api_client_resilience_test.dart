import 'package:chat_core/chat_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('request timeout is classified as retryable', () async {
    final client = ApiClient(
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response('{}', 200);
      }),
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'request_timeout')
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });

  test('premature connection close is classified as retryable', () async {
    final client = ApiClient(
      client: MockClient((_) async {
        throw http.ClientException('connection closed');
      }),
    );

    await expectLater(
      client.get('/health'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.code, 'code', 'connection_closed')
            .having((error) => error.isRetryable, 'isRetryable', isTrue),
      ),
    );
  });
}
