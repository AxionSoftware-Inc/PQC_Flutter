import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/device/device_prekey_service.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:pqc_chat_app/core/storage/session_storage.dart';
import 'package:pqc_chat_app/features/auth/data/auth_repository.dart';
import 'package:pqc_chat_app/features/auth/presentation/login_page.dart';
import 'package:pqc_chat_app/features/auth/session_controller.dart';
import 'package:pqc_chat_app/features/crypto/outbound_message_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('login page renders login form', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionController = SessionController(
      authRepository: AuthRepository(
        apiClient: ApiClient(),
        sessionStorage: SessionStorage(secretStore: _MemorySecretStore()),
        deviceIdentityService: DeviceIdentityService(),
        deviceKeyService: DeviceKeyService(),
        devicePreKeyService: DevicePreKeyService(),
        outboundMessageCache: OutboundMessageCache(
          secretStore: _MemorySecretStore(),
        ),
      ),
    );
    await sessionController.initialize();

    await tester.pumpWidget(
      MaterialApp(home: LoginPage(sessionController: sessionController)),
    );

    expect(find.text('PQC Chat Login'), findsOneWidget);
    expect(find.text('Ism'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}

class _MemorySecretStore extends LocalSecretStore {
  _MemorySecretStore() : super();

  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
