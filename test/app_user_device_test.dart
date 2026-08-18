import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/models/app_user.dart';
import 'dart:convert';

final _validMlKem768PublicKey = base64Encode(List<int>.filled(1184, 0));
final _nonCanonicalMlKem768PublicKey = base64Encode(
  List<int>.filled(1184, 0xff),
);

void main() {
  test(
    'device protocol capabilities are normalized and fail closed for legacy data',
    () {
      final legacy = AppUserDevice.fromJson(const {'device_id': 'legacy'});
      final v3 = AppUserDevice.fromJson(const {
        'device_id': 'v3-device',
        'supported_protocols': ['v3'],
      });

      expect(legacy.supportedProtocols, ['v2']);
      expect(legacy.supportsProtocol('v3'), isFalse);
      expect(v3.supportedProtocols, ['v2', 'v2.5', 'v3']);
      expect(v3.supportsProtocol('v3'), isTrue);
    },
  );

  test(
    'x25519 device key is usable only for valid 32-byte base64 public key',
    () {
      final validDevice = AppUserDevice(
        deviceId: 'device-1',
        deviceName: 'Tablet',
        platform: 'android',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        keyAlgorithm: 'x25519',
      );
      final invalidBase64Device = AppUserDevice(
        deviceId: 'device-2',
        deviceName: 'Mac',
        platform: 'macos',
        identityPublicKey: 'not-base64',
        keyAlgorithm: 'x25519',
      );
      final invalidLengthDevice = AppUserDevice(
        deviceId: 'device-3',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: 'AQID',
        keyAlgorithm: 'x25519',
      );
      final wrongAlgorithmDevice = AppUserDevice(
        deviceId: 'device-4',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        keyAlgorithm: 'demo',
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
      );
      final invalidBase64Device = AppUserDevice(
        deviceId: 'device-pqc-2',
        deviceName: 'Mac',
        platform: 'macos',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: 'not-base64',
        pqcAlgorithm: 'ml-kem-768',
      );
      final invalidLengthDevice = AppUserDevice(
        deviceId: 'device-pqc-3',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: 'AQID',
        pqcAlgorithm: 'ml-kem-768',
      );
      final wrongAlgorithmDevice = AppUserDevice(
        deviceId: 'device-pqc-4',
        deviceName: 'Phone',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: _validMlKem768PublicKey,
        pqcAlgorithm: 'demo',
      );
      final nonCanonicalDevice = AppUserDevice(
        deviceId: 'device-pqc-5',
        deviceName: 'Corrupted phone',
        platform: 'android',
        identityPublicKey: '',
        keyAlgorithm: '',
        pqcPublicKey: _nonCanonicalMlKem768PublicKey,
        pqcAlgorithm: 'ml-kem-768',
      );

      expect(validDevice.hasUsableMlKemKey, isTrue);
      expect(invalidBase64Device.hasUsableMlKemKey, isFalse);
      expect(invalidLengthDevice.hasUsableMlKemKey, isFalse);
      expect(wrongAlgorithmDevice.hasUsableMlKemKey, isFalse);
      expect(nonCanonicalDevice.hasUsableMlKemKey, isFalse);
    },
  );
}
