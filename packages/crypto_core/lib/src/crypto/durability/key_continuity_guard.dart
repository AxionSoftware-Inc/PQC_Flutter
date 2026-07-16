import 'crypto_durability_models.dart';
import 'key_material_registry.dart';

class KeyContinuityResult {
  const KeyContinuityResult({required this.current, required this.historical});

  final KeysetSnapshot current;
  final List<KeysetSnapshot> historical;
}

/// Keeps key rotation write-only for the new keyset. Existing keysets remain
/// readable and are never revoked by a normal device-key change.
class KeyContinuityGuard {
  const KeyContinuityGuard({required this.registry});

  final KeyMaterialRegistry registry;

  Future<KeyContinuityResult> ensureCurrentPreservingHistory() async {
    final current = await registry.ensureCurrentKeysetRegistered();
    final historical = await registry.readHistoricalDecryptKeysets();
    return KeyContinuityResult(current: current, historical: historical);
  }
}
