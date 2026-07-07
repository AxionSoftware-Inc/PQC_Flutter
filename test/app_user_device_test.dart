import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'dart:convert';

final _validMlKem768PublicKey = base64Encode(List<int>.filled(1184, 0));

void main() {
  test(
    'x25519 device key is usable only for valid 32-byte base64 public key',
    () {
      final validDevice = AppUserDevice(
        deviceId: 'device-1',
        deviceName: 'Tablet',
        platform: 'android',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      final invalidBase64Device = AppUserDevice(
        deviceId: 'device-2',
        deviceName: 'Mac',
        platform: 'macos',
        identityPublicKey: 'not-base64',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      final invalidLengthDevice = AppUserDevice(
        deviceId: 'device-3',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: 'AQID',
        keyAlgorithm: 'x25519',
        preKeys: [],
      );
      final wrongAlgorithmDevice = AppUserDevice(
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

  test(
    'ml-kem-768 device key is usable only for valid 1184-byte base64 public key',
    () {
      final validDevice = AppUserDevice(
        deviceId: 'device-pqc-1',
        deviceName: 'Tablet',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: _validMlKem768PublicKey,
        pqcAlgorithm: 'ml-kem-768',
        preKeys: [],
      );
      final invalidBase64Device = AppUserDevice(
        deviceId: 'device-pqc-2',
        deviceName: 'Mac',
        platform: 'macos',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: 'not-base64',
        pqcAlgorithm: 'ml-kem-768',
        preKeys: [],
      );
      final invalidLengthDevice = AppUserDevice(
        deviceId: 'device-pqc-3',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: 'AQID',
        pqcAlgorithm: 'ml-kem-768',
        preKeys: [],
      );
      final wrongAlgorithmDevice = AppUserDevice(
        deviceId: 'device-pqc-4',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: _validMlKem768PublicKey,
        pqcAlgorithm: 'demo',
        preKeys: [],
      );

      expect(validDevice.hasUsableMlKemKey, isTrue);
      expect(invalidBase64Device.hasUsableMlKemKey, isFalse);
      expect(invalidLengthDevice.hasUsableMlKemKey, isFalse);
      expect(wrongAlgorithmDevice.hasUsableMlKemKey, isFalse);
    },
  );
}
