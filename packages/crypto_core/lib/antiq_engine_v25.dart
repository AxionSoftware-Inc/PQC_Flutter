/// Public V2.5 engine SDK surface.
///
/// V2.5 is a release profile over the immutable V2 wire format. The host
/// supplies device-key and storage adapters; this entry point has no UI, HTTP
/// client or account-session dependency.
library;

export 'src/core/device/device_identity_service.dart';
export 'src/core/device/device_pqc_key_service.dart';
export 'src/core/device/device_pqc_signing_key_service.dart';
export 'src/crypto/attachment_crypto_service.dart';
export 'src/crypto/chat_cipher_algorithms.dart';
export 'src/crypto/chat_cipher_service.dart';
export 'src/crypto/chat_crypto_context.dart';
export 'src/crypto/chat_crypto_exceptions.dart';
export 'src/crypto/durability/key_material_registry.dart';
export 'src/crypto/durability/v2_protocol_contract.dart';
export 'src/crypto/group_key_store.dart';
export 'src/crypto/message_codec.dart';
export 'src/models/app_user.dart';
export 'src/models/attachment.dart';
export 'src/models/conversation.dart';
export 'src/models/conversation_key_envelope.dart';
export 'src/support/conversation_device_policy.dart';
