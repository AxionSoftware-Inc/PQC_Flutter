import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/network/api_client.dart';
import 'package:pqc_chat_app/core/storage/session_storage.dart';
import 'package:pqc_chat_app/features/auth/data/auth_repository.dart';
import 'package:pqc_chat_app/features/auth/presentation/login_page.dart';
import 'package:pqc_chat_app/features/auth/session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('login page renders login form', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final sessionController = SessionController(
      authRepository: AuthRepository(
        apiClient: ApiClient(),
        sessionStorage: SessionStorage(),
        deviceIdentityService: DeviceIdentityService(),
        deviceKeyService: DeviceKeyService(),
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
