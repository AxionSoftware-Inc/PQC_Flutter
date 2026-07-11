import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_signing_key_service.dart';
import 'package:pqc_chat_app/core/device/device_security_state_service.dart';
import 'package:pqc_chat_app/core/device/device_state_manager.dart';
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
    tester.view.physicalSize = const Size(1440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final secretStore = _MemorySecretStore();
    final deviceIdentityService = DeviceIdentityService();
    final deviceKeyService = DeviceKeyService(secretStore: secretStore);
    final devicePqcKeyService = DevicePqcKeyService(secretStore: secretStore);
    final devicePqcSigningKeyService = DevicePqcSigningKeyService(
      secretStore: secretStore,
    );
    final deviceSecurityStateService = DeviceSecurityStateService();

    final sessionController = SessionController(
      authRepository: AuthRepository(
        apiClient: ApiClient(),
        sessionStorage: SessionStorage(secretStore: secretStore),
        deviceIdentityService: deviceIdentityService,
        deviceKeyService: deviceKeyService,
        devicePqcKeyService: devicePqcKeyService,
        devicePqcSigningKeyService: devicePqcSigningKeyService,
        deviceSecurityStateService: deviceSecurityStateService,
        deviceStateManager: DeviceStateManager(
          deviceIdentityService: deviceIdentityService,
          deviceKeyService: deviceKeyService,
          devicePqcKeyService: devicePqcKeyService,
          devicePqcSigningKeyService: devicePqcSigningKeyService,
          deviceSecurityStateService: deviceSecurityStateService,
        ),
        outboundMessageCache: OutboundMessageCache(
          secretStore: secretStore,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: LoginPage(sessionController: sessionController)),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('PQC Messenger Workspace'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
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
