import 'package:flutter_test/flutter_test.dart';
import 'package:pqc_chat_app/app/modules/antiq_app_module.dart';
import 'package:pqc_chat_app/app/modules/antiq_app_module_registry.dart';

void main() {
  test('empty app module configuration keeps the core host isolated', () async {
    await AntiQAppModuleRegistry().initializeConfiguredModules();
  });

  test('module initialization receives the complete enabled set', () async {
    final module = _TestModule();
    // The registry is intentionally compile-time configured. This verifies
    // the extension contract itself without making test process environment
    // mutate the application startup policy.
    await module.initialize(
      const AntiQAppModuleContext(enabledModuleIds: {'rbac', 'tasks'}),
    );
    expect(module.enabled, {'rbac', 'tasks'});
  });
}

class _TestModule implements AntiQAppModule {
  Set<String>? enabled;

  @override
  String get id => 'test';

  @override
  Future<void> initialize(AntiQAppModuleContext context) async {
    enabled = context.enabledModuleIds;
  }
}
