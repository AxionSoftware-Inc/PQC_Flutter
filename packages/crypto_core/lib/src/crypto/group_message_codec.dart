import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:crypto_core/src/models/app_user.dart';
import 'package:crypto_core/src/models/conversation.dart';
import 'group_key_store.dart';
import 'durability/v2_protocol_contract.dart';

class GroupCipherMessageCodec {
  GroupCipherMessageCodec({required this._groupKeyStore, AesGcm? cipher})
    : _cipher = cipher ?? AesGcm.with256bits();

  static const prefix = PqcV2ProtocolContract.groupPrefix;
  static final _random = Random.secure();

  final GroupKeyProvider _groupKeyStore;
  final AesGcm _cipher;

  Future<String> encrypt({
    required Conversation conversation,
    required String plaintext,
    required Map<int, AppUser> usersById,
  }) async {
    final keyMaterial = await _groupKeyStore.getOrCreateKey(
      conversation: conversation,
      usersById: usersById,
    );
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(keyMaterial.secretKeyBytes),
      nonce: nonce,
    );

    final document = <String, dynamic>{
      'protocol_version': PqcV2ProtocolContract.protocolVersion,
      'algorithm': PqcV2ProtocolContract.groupAlgorithm,
      'conversation_id': conversation.id,
      'conversation_type': conversation.type,
      'group_epoch_id': keyMaterial.keyId,
      'nonce': base64Encode(secretBox.nonce),
      'ciphertext': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    final encodedDocument = base64UrlEncode(
      utf8.encode(jsonEncode(document)),
    ).replaceAll('=', '');
    return '$prefix:$encodedDocument';
  }

  Future<String> decrypt({
    required Conversation conversation,
    required String payload,
    required Map<int, AppUser> usersById,
  }) async {
    try {
      if (!payload.startsWith('$prefix:')) return '[history-unavailable]';
      final encoded = payload.substring(prefix.length + 1);
      final padded = encoded.padRight(
        encoded.length + ((4 - encoded.length % 4) % 4),
        '=',
      );
      final document =
          jsonDecode(utf8.decode(base64Url.decode(padded)))
              as Map<String, dynamic>;
      if (document['protocol_version'] !=
              PqcV2ProtocolContract.protocolVersion ||
          document['algorithm'] != PqcV2ProtocolContract.groupAlgorithm ||
          document['conversation_id'] != conversation.id ||
          document['conversation_type'] != conversation.type) {
        return '[decrypt-error]';
      }

      final keyMaterial = await _groupKeyStore.getExistingKey(
        conversation: conversation,
        usersById: usersById,
        requestedKeyId: document['group_epoch_id'] as String?,
      );
      if (keyMaterial == null) {
        return '[decrypt-error]';
      }

      final clearBytes = await _cipher.decrypt(
        SecretBox(
          base64Decode(document['ciphertext'] as String),
          nonce: base64Decode(document['nonce'] as String),
          mac: Mac(base64Decode(document['mac'] as String)),
        ),
        secretKey: SecretKey(keyMaterial.secretKeyBytes),
      );
      return utf8.decode(clearBytes);
    } catch (_) {
      return '[decrypt-error]';
    }
  }
}
