/// Public V3 engine SDK surface.
///
/// V3 remains isolated from the V2.5 writer. It retains V2 compatibility only
/// through an explicit read-only decoder adapter.
library;

export 'src/core/device/device_identity_service.dart';
export 'src/core/device/device_pqc_key_service.dart';
export 'src/core/device/device_pqc_signing_key_service.dart';
export 'src/crypto/durability/crypto_durability_models.dart';
export 'src/crypto/durability/key_material_registry.dart';
export 'src/crypto/v3/pqc_v3_crypto_adapter.dart';
export 'src/crypto/v3/v2_compatibility_decoder.dart';
export 'src/crypto/v3/v3_attachment_codec.dart';
export 'src/crypto/v3/v3_capabilities.dart';
export 'src/crypto/v3/v3_chat_cipher_algorithm.dart';
export 'src/crypto/v3/v3_codec_adapters.dart';
export 'src/crypto/v3/v3_crypto_adapter.dart';
export 'src/crypto/v3/v3_engine_manager.dart';
export 'src/crypto/v3/v3_engine_module.dart';
export 'src/crypto/v3/v3_envelope.dart';
export 'src/crypto/v3/v3_message_codecs.dart';
export 'src/crypto/v3/v3_protocol_contract.dart';
export 'src/models/conversation.dart';
