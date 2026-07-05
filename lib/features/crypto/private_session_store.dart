import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/local_secret_store.dart';

class PrivateSessionState {
  const PrivateSessionState({
    required this.conversationId,
    required this.peerDeviceId,
    required this.peerIdentityPublicKey,
    required this.rootKey,
    required this.sendingChainKey,
    required this.receivingChainKey,
    required this.nextLocalCounter,
    required this.nextRemoteCounter,
    required this.skippedRemoteMessageKeys,
    required this.establishedBy,
  });

  final int conversationId;
  final String peerDeviceId;
  final String peerIdentityPublicKey;
  final String rootKey;
  final String sendingChainKey;
  final String receivingChainKey;
  final int nextLocalCounter;
  final int nextRemoteCounter;
  final Map<String, String> skippedRemoteMessageKeys;
  final String establishedBy;

  PrivateSessionState copyWith({
    int? conversationId,
    String? peerDeviceId,
    String? peerIdentityPublicKey,
    String? rootKey,
    String? sendingChainKey,
    String? receivingChainKey,
    int? nextLocalCounter,
    int? nextRemoteCounter,
    Map<String, String>? skippedRemoteMessageKeys,
    String? establishedBy,
  }) {
    return PrivateSessionState(
      conversationId: conversationId ?? this.conversationId,
      peerDeviceId: peerDeviceId ?? this.peerDeviceId,
      peerIdentityPublicKey:
          peerIdentityPublicKey ?? this.peerIdentityPublicKey,
      rootKey: rootKey ?? this.rootKey,
      sendingChainKey: sendingChainKey ?? this.sendingChainKey,
      receivingChainKey: receivingChainKey ?? this.receivingChainKey,
      nextLocalCounter: nextLocalCounter ?? this.nextLocalCounter,
      nextRemoteCounter: nextRemoteCounter ?? this.nextRemoteCounter,
      skippedRemoteMessageKeys:
          skippedRemoteMessageKeys ?? this.skippedRemoteMessageKeys,
      establishedBy: establishedBy ?? this.establishedBy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'conversation_id': conversationId,
      'peer_device_id': peerDeviceId,
      'peer_identity_public_key': peerIdentityPublicKey,
      'root_key': rootKey,
      'sending_chain_key': sendingChainKey,
      'receiving_chain_key': receivingChainKey,
      'next_local_counter': nextLocalCounter,
      'next_remote_counter': nextRemoteCounter,
      'skipped_remote_message_keys': skippedRemoteMessageKeys,
      'established_by': establishedBy,
    };
  }

  factory PrivateSessionState.fromJson(Map<String, dynamic> json) {
    return PrivateSessionState(
      conversationId: json['conversation_id'] as int,
      peerDeviceId: json['peer_device_id'] as String,
      peerIdentityPublicKey: json['peer_identity_public_key'] as String? ?? '',
      rootKey: json['root_key'] as String,
      sendingChainKey: json['sending_chain_key'] as String? ?? '',
      receivingChainKey: json['receiving_chain_key'] as String? ?? '',
      nextLocalCounter: json['next_local_counter'] as int? ?? 0,
      nextRemoteCounter: json['next_remote_counter'] as int? ?? 0,
      skippedRemoteMessageKeys:
          (json['skipped_remote_message_keys'] as Map<String, dynamic>? ??
                  const {})
              .map((key, value) => MapEntry(key, value as String)),
      establishedBy: json['established_by'] as String? ?? 'legacy',
    );
  }
}

class PrivateSessionStore {
  static const _sessionStoragePrefix = 'private_session_';

  PrivateSessionStore({LocalSecretStore? secretStore})
    : _secretStore = secretStore ?? LocalSecretStore();

  final LocalSecretStore _secretStore;

  Future<PrivateSessionState?> readSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    final storageKey = _storageKey(conversationId, peerDeviceId);
    final raw = await _secretStore.read(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final session = PrivateSessionState.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (!_isValidSession(session)) {
        await _secretStore.delete(storageKey);
        return null;
      }
      return session;
    } catch (_) {
      await _secretStore.delete(storageKey);
      return null;
    }
  }

  Future<bool> hasSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    return await readSession(
          conversationId: conversationId,
          peerDeviceId: peerDeviceId,
        ) !=
        null;
  }

  Future<bool> hasMatchingSession({
    required int conversationId,
    required String peerDeviceId,
    required String peerIdentityPublicKey,
  }) async {
    final session = await readSession(
      conversationId: conversationId,
      peerDeviceId: peerDeviceId,
    );
    if (session == null) {
      return false;
    }
    return session.peerIdentityPublicKey == peerIdentityPublicKey;
  }

  Future<void> writeSession(PrivateSessionState session) async {
    await _secretStore.write(
      key: _storageKey(session.conversationId, session.peerDeviceId),
      value: jsonEncode(session.toJson()),
    );
  }

  Future<void> establishSession({
    required int conversationId,
    required String peerDeviceId,
    required String peerIdentityPublicKey,
    required String rootKey,
    required String sendingChainKey,
    required String receivingChainKey,
    required String establishedBy,
  }) async {
    final existing = await readSession(
      conversationId: conversationId,
      peerDeviceId: peerDeviceId,
    );
    if (existing != null && existing.rootKey == rootKey) {
      return;
    }

    await writeSession(
      PrivateSessionState(
        conversationId: conversationId,
        peerDeviceId: peerDeviceId,
        peerIdentityPublicKey: peerIdentityPublicKey,
        rootKey: rootKey,
        sendingChainKey: sendingChainKey,
        receivingChainKey: receivingChainKey,
        nextLocalCounter: 0,
        nextRemoteCounter: 0,
        skippedRemoteMessageKeys: const {},
        establishedBy: establishedBy,
      ),
    );
  }

  Future<void> deleteSession({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    await _secretStore.delete(_storageKey(conversationId, peerDeviceId));
  }

  Future<int> takeNextOutgoingCounter({
    required int conversationId,
    required String peerDeviceId,
  }) async {
    final existing = await readSession(
      conversationId: conversationId,
      peerDeviceId: peerDeviceId,
    );
    if (existing == null) {
      throw StateError('Private session not found.');
    }

    final counter = existing.nextLocalCounter;
    await writeSession(
      existing.copyWith(nextLocalCounter: existing.nextLocalCounter + 1),
    );
    return counter;
  }

  Future<void> updateSession(PrivateSessionState session) async {
    await writeSession(session);
  }

  Future<void> clearAllSessions() async {
    final managedKeys = await _secretStoreManagedKeys();
    for (final key in managedKeys.where(
      (item) => item.startsWith(_sessionStoragePrefix),
    )) {
      await _secretStore.delete(key);
    }
  }

  String _storageKey(int conversationId, String peerDeviceId) {
    return 'private_session_${conversationId}_$peerDeviceId';
  }

  bool _isValidSession(PrivateSessionState session) {
    return _isBase64Bytes(session.rootKey, expectedLength: 32) &&
        _isBase64Bytes(session.sendingChainKey, expectedLength: 32) &&
        _isBase64Bytes(session.receivingChainKey, expectedLength: 32);
  }

  bool _isBase64Bytes(String value, {required int expectedLength}) {
    if (value.isEmpty) {
      return false;
    }
    try {
      return base64Decode(value).length == expectedLength;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> _secretStoreManagedKeys() async {
    final preferences = await SharedPreferences.getInstance();
    return preferences.getStringList('local_secret_store_managed_keys') ??
        const <String>[];
  }
}
