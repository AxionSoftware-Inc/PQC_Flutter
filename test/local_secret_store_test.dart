import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pqc_chat_app/core/storage/local_secret_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fallback storage does not leave plaintext in shared preferences', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalSecretStore(secureStorage: _ThrowingSecureStorage());

    await store.write(key: 'secret_key', value: 'super-secret-value');

    final preferences = await SharedPreferences.getInstance();
    final rawStored = preferences.getString('secret_key');
    final restored = await store.read('secret_key');

    expect(rawStored, isNotNull);
    expect(rawStored, isNot('super-secret-value'));
    expect(rawStored, startsWith('local_secret:v1:'));
    expect(restored, 'super-secret-value');
  });

  test('fallback storage migrates old plaintext preference entries', () async {
    SharedPreferences.setMockInitialValues({
      'legacy_secret': 'legacy-value',
    });
    final store = LocalSecretStore(secureStorage: _ThrowingSecureStorage());

    final restored = await store.read('legacy_secret');
    final preferences = await SharedPreferences.getInstance();
    final rawStored = preferences.getString('legacy_secret');

    expect(restored, 'legacy-value');
    expect(rawStored, isNot('legacy-value'));
    expect(rawStored, startsWith('local_secret:v1:'));
  });
}

class _ThrowingSecureStorage extends FlutterSecureStorage {
  @override
  Future<void> write({
    required String key,
    String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw MissingPluginException();
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw MissingPluginException();
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    throw MissingPluginException();
  }
}
