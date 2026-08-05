import 'antiq_app_module.dart';

/// Resolves optional app modules with the same fail-closed rule as backend
/// plugins. An unknown module must never result in a partly-enabled client.
class AntiQAppModuleRegistry {
  AntiQAppModuleRegistry({Iterable<AntiQAppModule> modules = const []})
    : _modules = {for (final module in modules) module.id: module};

  final Map<String, AntiQAppModule> _modules;

  Future<void> initializeConfiguredModules() async {
    const raw = String.fromEnvironment('ANTIQ_APP_MODULES', defaultValue: '');
    final requested = raw
        .split(',')
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    final unknown = requested.difference(_modules.keys.toSet());
    if (unknown.isNotEmpty) {
      throw StateError('Unknown antiQ app module(s): ${unknown.join(', ')}.');
    }
    final context = AntiQAppModuleContext(enabledModuleIds: requested);
    for (final id in requested) {
      await _modules[id]!.initialize(context);
    }
  }
}
