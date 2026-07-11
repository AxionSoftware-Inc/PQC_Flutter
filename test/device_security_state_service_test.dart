import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/core/device/device_identity_service.dart';
import 'package:pqc_chat_app/core/device/device_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_key_service.dart';
import 'package:pqc_chat_app/core/device/device_pqc_signing_key_service.dart';
import 'package:pqc_chat_app/core/device/device_security_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'rotates installation id when keys change under same device id',
    () async {
      SharedPreferences.setMockInitialValues({});
      final service = DeviceSecurityStateService();
      final identityService = _FakeDeviceIdentityService();

      final first = await service.ensureConsistentState(
        deviceIdentityService: identityService,
        deviceKeyService: _FakeDeviceKeyService('identity-a'),
        devicePqcKeyService: _FakeDevicePqcKeyService('pqc-a'),
        devicePqcSigningKeyService: _FakeDevicePqcSigningKeyService('sign-a'),
      );
      final second = await service.ensureConsistentState(
        deviceIdentityService: identityService,
        deviceKeyService: _FakeDeviceKeyService('identity-b'),
        devicePqcKeyService: _FakeDevicePqcKeyService('pqc-b'),
        devicePqcSigningKeyService: _FakeDevicePqcSigningKeyService('sign-b'),
      );

      expect(first.didRotateInstallation, isFalse);
      expect(second.didRotateInstallation, isTrue);
      expect(second.deviceIdentity.id, isNot(first.deviceIdentity.id));
    },
  );
}

class _FakeDeviceIdentityService extends DeviceIdentityService {
  String _currentId = 'device-a';
  int _rotationCount = 0;

  @override
  Future<DeviceIdentity> getIdentity() async {
    return DeviceIdentity(
      id: _currentId,
      deviceName: 'test-device',
      platform: 'test',
    );
  }

  @override
  Future<DeviceIdentity> rotateIdentity() async {
    _rotationCount += 1;
    _currentId = 'device-rotated-$_rotationCount';
    return DeviceIdentity(
      id: _currentId,
      deviceName: 'test-device',
      platform: 'test',
    );
  }
}

class _FakeDeviceKeyService extends DeviceKeyService {
  _FakeDeviceKeyService(this.publicKey);

  final String publicKey;

  @override
  Future<DeviceKeyMaterial> getOrCreateKeyMaterial() async {
    return DeviceKeyMaterial(
      publicKey: publicKey,
      privateKey: 'private-$publicKey',
      algorithm: 'x25519',
    );
  }
}

class _FakeDevicePqcKeyService extends DevicePqcKeyService {
  _FakeDevicePqcKeyService(this.publicKey);

  final String publicKey;

  @override
  bool get isSupportedOnCurrentPlatform => true;

  @override
  Future<DevicePqcKeyMaterial> getOrCreateKeyMaterial() async {
    return DevicePqcKeyMaterial(
      publicKey: publicKey,
      secretKey: 'secret-$publicKey',
      algorithm: 'ml-kem-768',
    );
  }
}

class _FakeDevicePqcSigningKeyService extends DevicePqcSigningKeyService {
  _FakeDevicePqcSigningKeyService(this.publicKey);

  final String publicKey;

  @override
  Future<DevicePqcSigningKeyMaterial> getOrCreateKeyMaterial() async {
    return DevicePqcSigningKeyMaterial(
      publicKey: publicKey,
      secretKey: 'secret-$publicKey',
      algorithm: 'ml-dsa-65',
    );
  }
}
