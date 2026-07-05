import '../../core/models/app_user.dart';

class PeerPreKeySelectionService {
  Future<AppUserPreKey?> reserveNextPreKey(AppUserDevice device) async {
    for (final preKey in device.preKeys) {
      if (preKey.hasUsablePublicKey) {
        return preKey;
      }
    }

    return null;
  }
}
