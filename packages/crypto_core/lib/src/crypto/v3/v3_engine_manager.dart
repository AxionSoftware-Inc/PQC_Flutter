import 'v3_engine_module.dart';
import '../durability/crypto_durability_models.dart';

/// Isolated v3 engine coordinator. It is not wired into production until a
/// module is registered and the compatibility gate is explicitly opened.
class V3EngineManager {
  V3EngineManager({required V3EngineModule module}) : _module = module {
    if (module.formatId.trim().isEmpty ||
        module.privatePrefix.trim().isEmpty ||
        module.groupPrefix.trim().isEmpty) {
      throw ArgumentError(
        'A v3 engine module needs stable format identifiers.',
      );
    }
  }

  final V3EngineModule _module;
  bool _productionWriteGate = false;

  V3EngineModule get module => _module;
  bool get canWriteProduction => _productionWriteGate;

  void openProductionWriteGate({required String approval}) {
    if (approval != 'V3_COMPATIBILITY_APPROVED') {
      throw StateError('V3 compatibility approval is required before writing.');
    }
    _productionWriteGate = true;
  }

  String encode({
    required String plaintext,
    required Map<String, dynamic> context,
  }) {
    if (!_productionWriteGate) {
      throw StateError('V3 writer is draft-only until compatibility approval.');
    }
    return _module.encoder.encode(plaintext: plaintext, context: context);
  }

  Future<DecryptionOutcome> decode({
    required String payload,
    required Map<String, dynamic> context,
  }) {
    return _module.decoder.decode(payload: payload, context: context);
  }
}
