import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:pqcrypto/pqcrypto.dart';
import 'package:pqc_engine_sdk/pqc_engine_sdk.dart' as sdk;

/// Pure primitive adapter used by the Flutter host when it runs the SDK V3
/// engine. Key lifecycle remains in KeyMaterialRegistry; the SDK receives the
/// selected keyset as explicit arguments and owns wire serialization.
class PqcV3SdkPrimitiveSuite implements sdk.PqcPrimitiveSuite {
  PqcV3SdkPrimitiveSuite({Random? random})
    : _random = random ?? Random.secure(),
      _kem = PqcKem.kyber768,
      _signingParams = DilithiumParams.mlDsa65,
      _cipher = AesGcm.with256bits();

  final Random _random;
  final KyberKem _kem;
  final DilithiumParams _signingParams;
  final AesGcm _cipher;

  @override
  sdk.PqcDeviceKeyset generateDeviceKeyset(String deviceId) {
    final (kemPublic, kemSecret) = _kem.generateKeyPair();
    final (signingPublic, signingSecret) = MlDsa.generateKeyPair(
      _signingParams,
    );
    return sdk.PqcDeviceKeyset(
      deviceId: deviceId,
      kemPublicKeyBase64: base64Encode(kemPublic),
      kemSecretKeyBase64: base64Encode(kemSecret),
      signingPublicKeyBase64: base64Encode(signingPublic),
      signingSecretKeyBase64: base64Encode(signingSecret),
    );
  }

  @override
  sdk.PqcKemEnvelope encapsulate(String publicKeyBase64) {
    final (ciphertext, sharedSecret) = _kem.encapsulate(
      base64Decode(publicKeyBase64),
    );
    return sdk.PqcKemEnvelope(
      ciphertextBase64: base64Encode(ciphertext),
      sharedSecret: sharedSecret,
    );
  }

  @override
  Uint8List decapsulate({
    required String ciphertextBase64,
    required String secretKeyBase64,
  }) => Uint8List.fromList(
    _kem.decapsulate(
      base64Decode(secretKeyBase64),
      base64Decode(ciphertextBase64),
    ),
  );

  @override
  String sign({required List<int> message, required String secretKeyBase64}) =>
      base64Encode(
        MlDsa.sign(
          base64Decode(secretKeyBase64),
          Uint8List.fromList(message),
          _signingParams,
          ctx: Uint8List.fromList('pqc-chat-device-sign-v1'.codeUnits),
        ),
      );

  @override
  bool verify({
    required List<int> message,
    required String signatureBase64,
    required String publicKeyBase64,
  }) {
    try {
      return MlDsa.verify(
        base64Decode(publicKeyBase64),
        Uint8List.fromList(message),
        base64Decode(signatureBase64),
        _signingParams,
        ctx: Uint8List.fromList('pqc-chat-device-sign-v1'.codeUnits),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<sdk.PqcAeadBox> encryptAead({
    required List<int> plaintext,
    required List<int> key,
    required List<int> nonce,
    List<int> aad = const [],
  }) async {
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    return sdk.PqcAeadBox(
      nonce: box.nonce,
      ciphertext: box.cipherText,
      mac: box.mac.bytes,
    );
  }

  @override
  Future<Uint8List> decryptAead({
    required sdk.PqcAeadBox box,
    required List<int> key,
    List<int> aad = const [],
  }) async {
    final clear = await _cipher.decrypt(
      SecretBox(box.ciphertext, nonce: box.nonce, mac: Mac(box.mac)),
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  @override
  Future<Uint8List> deriveKey({
    required List<int> secret,
    required List<int> nonce,
    required List<int> info,
    int length = 32,
  }) async {
    final key = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: length,
    ).deriveKey(secretKey: SecretKey(secret), nonce: nonce, info: info);
    return Uint8List.fromList(await key.extractBytes());
  }

  @override
  Uint8List randomBytes(int length) => Uint8List.fromList(
    List<int>.generate(length, (_) => _random.nextInt(256)),
  );

  @override
  Uint8List sha256(List<int> value) =>
      Uint8List.fromList(crypto.sha256.convert(value).bytes);
}
