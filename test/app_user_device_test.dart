import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';

void main() {
  test(
    'x25519 device key is usable only for valid 32-byte base64 public key',
    () {
      const validDevice = AppUserDevice(
        deviceId: 'device-1',
        deviceName: 'Tablet',
        platform: 'android',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      const invalidBase64Device = AppUserDevice(
        deviceId: 'device-2',
        deviceName: 'Mac',
        platform: 'macos',
        identityPublicKey: 'not-base64',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      const invalidLengthDevice = AppUserDevice(
        deviceId: 'device-3',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: 'AQID',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      const wrongAlgorithmDevice = AppUserDevice(
        deviceId: 'device-4',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        keyAlgorithm: 'demo',
        preKeys: [],
      );

      expect(validDevice.hasUsableX25519Key, isTrue);
      expect(invalidBase64Device.hasUsableX25519Key, isFalse);
      expect(invalidLengthDevice.hasUsableX25519Key, isFalse);
      expect(wrongAlgorithmDevice.hasUsableX25519Key, isFalse);
    },
  );
}
