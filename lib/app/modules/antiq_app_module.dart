import 'dart:async';

/// A tenant feature boundary for the mobile host application.
///
/// Modules may register navigation, UI surfaces and adapters, but must not
/// mutate the encrypted chat/session core.  The core is the only built-in
/// module; commercial extensions are added explicitly by their package.
abstract interface class AntiQAppModule {
  String get id;

  FutureOr<void> initialize(AntiQAppModuleContext context);
}

class AntiQAppModuleContext {
  const AntiQAppModuleContext({required this.enabledModuleIds});

  final Set<String> enabledModuleIds;
}
