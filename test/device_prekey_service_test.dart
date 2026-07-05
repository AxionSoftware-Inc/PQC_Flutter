import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_prekey_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ensurePreKeys creates and reuses a stable public prekey batch',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = DevicePreKeyService();

      final firstBatch = await service.ensurePreKeys(minimumCount: 4);
      final secondBatch = await service.ensurePreKeys(minimumCount: 4);

      expect(firstBatch.length, 4);
      expect(secondBatch.length, 4);
      expect(secondBatch, firstBatch);
    },
  );
}
