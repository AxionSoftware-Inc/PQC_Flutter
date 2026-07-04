import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

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
  static const _uuid = Uuid();

  Future<DeviceIdentity> getIdentity() async {
    final preferences = await SharedPreferences.getInstance();
    var deviceId = preferences.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await preferences.setString(_deviceIdKey, deviceId);
    }

    final platform = _platformName();
    return DeviceIdentity(
      id: deviceId,
      deviceName: 'flutter-$platform',
      platform: platform,
    );
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
