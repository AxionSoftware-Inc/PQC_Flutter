import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../storage/local_secret_store.dart';

class DeviceIdentity {
  const DeviceIdentity({
    required this.id,
    required this.deviceName,
    required this.platform,
  });

  final String id;
  final String deviceName;
  final String platform;
}

class DeviceIdentityService {
  static const _deviceIdKey = 'device_installation_id';
  static const _deviceNameKey = 'device_installation_name';
  static const _uuid = Uuid();

  DeviceIdentityService({
    LocalSecretStore? secretStore,
    DeviceInfoPlugin? deviceInfoPlugin,
  }) : _secretStore = secretStore ?? LocalSecretStore(),
       _deviceInfoPlugin = deviceInfoPlugin ?? DeviceInfoPlugin();

  final LocalSecretStore _secretStore;
  final DeviceInfoPlugin _deviceInfoPlugin;

  Future<DeviceIdentity> getIdentity() async {
    var deviceId = await _secretStore.read(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _secretStore.write(key: _deviceIdKey, value: deviceId);
    }

    final platform = _platformName();
    final deviceName = await _resolveDeviceName(platform: platform);
    return DeviceIdentity(
      id: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
  }

  Future<DeviceIdentity> rotateIdentity() async {
    final deviceId = _uuid.v4();
    await _secretStore.write(key: _deviceIdKey, value: deviceId);
    final platform = _platformName();
    final deviceName = await _resolveDeviceName(platform: platform);
    return DeviceIdentity(
      id: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
  }

  Future<String> _resolveDeviceName({required String platform}) async {
    final existing = await _secretStore.read(_deviceNameKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final deviceName = await _readNativeDeviceName(platform);
    await _secretStore.write(key: _deviceNameKey, value: deviceName);
    return deviceName;
  }

  Future<String> _readNativeDeviceName(String platform) async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _deviceInfoPlugin.androidInfo;
          final brand = info.brand.trim();
          final model = info.model.trim();
          final device = [brand, model].where((item) => item.isNotEmpty).join(' ');
          return device.isEmpty ? 'Android Device' : device;
        case TargetPlatform.iOS:
          final info = await _deviceInfoPlugin.iosInfo;
          final name = info.utsname.machine.trim();
          final model = info.model.trim();
          final device = [model, name].where((item) => item.isNotEmpty).join(' ');
          return device.isEmpty ? 'iPhone' : device;
        case TargetPlatform.macOS:
          final info = await _deviceInfoPlugin.macOsInfo;
          return info.model.trim().isEmpty ? 'Mac' : info.model.trim();
        case TargetPlatform.windows:
          final info = await _deviceInfoPlugin.windowsInfo;
          return info.computerName.trim().isEmpty
              ? 'Windows PC'
              : info.computerName.trim();
        case TargetPlatform.linux:
          final info = await _deviceInfoPlugin.linuxInfo;
          return info.prettyName.trim().isEmpty
              ? 'Linux Device'
              : info.prettyName.trim();
        case TargetPlatform.fuchsia:
          return 'Fuchsia Device';
      }
    } catch (_) {
      return '${platform.toUpperCase()} Device';
    }
  }

  String _platformName() {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
