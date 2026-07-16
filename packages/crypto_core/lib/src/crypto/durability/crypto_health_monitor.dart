import 'key_material_registry.dart';
import 'key_storage_integrity.dart';

class CryptoHealthSnapshot {
  const CryptoHealthSnapshot({
    required this.healthy,
    required this.keysetCount,
    required this.historicalKeysetCount,
    this.error,
  });

  final bool healthy;
  final int keysetCount;
  final int historicalKeysetCount;
  final String? error;
}

/// Read-only health gate used before publishing recovery state or sending.
/// It never repairs by deleting keys; corruption is surfaced explicitly.
class CryptoHealthMonitor {
  const CryptoHealthMonitor({required this.registry});

  final KeyMaterialRegistry registry;

  Future<CryptoHealthSnapshot> check() async {
    try {
      final all = await registry.readAllKeysets();
      final historical = all.where((item) => item.isHistoricalReadEnabled);
      return CryptoHealthSnapshot(
        healthy: all.isNotEmpty,
        keysetCount: all.length,
        historicalKeysetCount: historical.length,
      );
    } on KeysetIntegrityException catch (error) {
      return CryptoHealthSnapshot(
        healthy: false,
        keysetCount: 0,
        historicalKeysetCount: 0,
        error: error.toString(),
      );
    } catch (error) {
      return CryptoHealthSnapshot(
        healthy: false,
        keysetCount: 0,
        historicalKeysetCount: 0,
        error: error.toString(),
      );
    }
  }
}
