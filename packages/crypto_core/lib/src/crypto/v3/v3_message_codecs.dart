import 'dart:convert';
import 'dart:math';

import 'v3_crypto_adapter.dart';
import 'v3_envelope.dart';
import 'pqc_v3_crypto_adapter.dart';

class V3DeviceRecipient {
  const V3DeviceRecipient({
    required this.deviceId,
    required this.keysetId,
    required this.publicKey,
  });

  final String deviceId;
  final String keysetId;
  final String publicKey;
}

class V3CodecContext {
  const V3CodecContext({
    required this.conversationId,
    required this.conversationType,
    required this.messageId,
    required this.senderDeviceId,
    required this.senderKeysetId,
    required this.signingPublicKey,
    required this.localDeviceId,
    required this.localKeysetId,
    this.localSecretKey,
    this.recipients = const [],
    this.groupEpochKey,
  });

  final int conversationId;
  final String conversationType;
  final String messageId;
  final String senderDeviceId;
  final String senderKeysetId;
  final String signingPublicKey;
  final String localDeviceId;
  final String localKeysetId;
  final String? localSecretKey;
  final List<V3DeviceRecipient> recipients;
  final List<int>? groupEpochKey;
}

class V3MessageCodec {
  V3MessageCodec({required this.crypto});

  final V3CryptoAdapter crypto;
  static final _random = Random.secure();

  Future<String> encryptPrivate({
    required V3CodecContext context,
    required String plaintext,
  }) => _encrypt(isGroup: false, context: context, plaintext: plaintext);

  Future<String> encryptGroup({
    required V3CodecContext context,
    required String plaintext,
  }) => _encrypt(isGroup: true, context: context, plaintext: plaintext);

  Future<String> _encrypt({
    required bool isGroup,
    required V3CodecContext context,
    required String plaintext,
  }) async {
    if (context.recipients.isEmpty) {
      throw StateError('V3 message needs at least one recipient device.');
    }
    final contentKey = isGroup && context.groupEpochKey != null
        ? List<int>.of(context.groupEpochKey!)
        : List<int>.generate(32, (_) => _random.nextInt(256));
    if (contentKey.length != 32) {
      throw ArgumentError('V3 content key must be exactly 32 bytes.');
    }
    final ad = PqcV3AssociatedData.forMessage(context);
    final encrypted = await crypto.encrypt(
      plaintext: utf8.encode(plaintext),
      associatedData: ad,
      context: {'content_key': contentKey, 'nonce': _nonce()},
    );
    final wraps = <V3RecipientWrap>[];
    for (final recipient in context.recipients) {
      final encapsulated = await crypto.encapsulate(recipient.publicKey);
      final wrapped = await crypto.encrypt(
        plaintext: contentKey,
        associatedData: utf8.encode(
          '${context.messageId}:${recipient.deviceId}',
        ),
        context: {'content_key': encapsulated.$2, 'nonce': _nonce()},
      );
      wraps.add(
        V3RecipientWrap(
          deviceId: recipient.deviceId,
          keysetId: recipient.keysetId,
          kemCiphertext: encapsulated.$1,
          wrappedKey: base64Encode(wrapped),
        ),
      );
    }
    final unsigned = V3Envelope(
      isGroup: isGroup,
      messageId: context.messageId,
      senderDeviceId: context.senderDeviceId,
      keysetId: context.senderKeysetId,
      ciphertext: base64Encode(encrypted),
      conversationId: context.conversationId,
      conversationType: context.conversationType,
      senderKeysetId: context.senderKeysetId,
      signingPublicKey: context.signingPublicKey,
      wraps: wraps,
    );
    final signature = await crypto.sign(
      utf8.encode(unsigned.unsignedCanonicalJson()),
    );
    return V3Envelope(
      isGroup: isGroup,
      messageId: context.messageId,
      senderDeviceId: context.senderDeviceId,
      keysetId: context.senderKeysetId,
      ciphertext: base64Encode(encrypted),
      conversationId: context.conversationId,
      conversationType: context.conversationType,
      senderKeysetId: context.senderKeysetId,
      signingPublicKey: context.signingPublicKey,
      wraps: wraps,
      signature: signature,
    ).encode();
  }

  Future<String> decrypt({
    required V3CodecContext context,
    required String payload,
  }) async {
    final envelope = V3Envelope.decode(payload);
    final effectiveContext = V3CodecContext(
      conversationId: context.conversationId,
      conversationType: context.conversationType,
      messageId: context.messageId.isEmpty
          ? envelope.messageId
          : context.messageId,
      senderDeviceId: context.senderDeviceId,
      senderKeysetId: context.senderKeysetId,
      signingPublicKey: context.signingPublicKey,
      localDeviceId: context.localDeviceId,
      localKeysetId: context.localKeysetId,
      localSecretKey: context.localSecretKey,
      recipients: context.recipients,
      groupEpochKey: context.groupEpochKey,
    );
    if (envelope.conversationId != effectiveContext.conversationId ||
        envelope.conversationType != effectiveContext.conversationType ||
        envelope.messageId != effectiveContext.messageId ||
        envelope.signingPublicKey == null ||
        envelope.signature == null) {
      throw const FormatException('V3 envelope context mismatch.');
    }
    final verified = crypto.verify(
      publicKey: envelope.signingPublicKey!,
      signature: envelope.signature!,
      message: utf8.encode(envelope.unsignedCanonicalJson()),
    );
    if (!verified) {
      throw const FormatException('V3 signature verification failed.');
    }
    final wrap = envelope.wraps
        .where(
          (item) =>
              item.deviceId == context.localDeviceId &&
              item.keysetId == context.localKeysetId,
        )
        .firstOrNull;
    if (wrap == null) {
      throw StateError('V3 recipient key wrap is missing.');
    }
    final historicalSecretKey = context.localSecretKey;
    final shared = historicalSecretKey == null
        ? await crypto.decapsulate(wrap.kemCiphertext)
        : await crypto.decapsulateWithSecretKey(
            ciphertext: wrap.kemCiphertext,
            secretKey: historicalSecretKey,
          );
    final contentKey = await crypto.decrypt(
      ciphertext: base64Decode(wrap.wrappedKey),
      associatedData: utf8.encode(
        '${effectiveContext.messageId}:${effectiveContext.localDeviceId}',
      ),
      context: {'content_key': shared},
    );
    final plaintext = await crypto.decrypt(
      ciphertext: base64Decode(envelope.ciphertext),
      associatedData: PqcV3AssociatedData.forMessage(effectiveContext),
      context: {'content_key': contentKey},
    );
    return utf8.decode(plaintext);
  }

  List<int> _nonce() => List<int>.generate(12, (_) => _random.nextInt(256));
}

class PqcV3AssociatedData {
  static List<int> forMessage(V3CodecContext context) =>
      PqcV3CryptoAdapter.associatedData(
        conversationId: context.conversationId,
        conversationType: context.conversationType,
        messageId: context.messageId,
        senderDeviceId: context.senderDeviceId,
        keysetId: context.senderKeysetId,
      );
}
