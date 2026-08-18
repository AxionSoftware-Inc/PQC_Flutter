import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'attachment_transfer_models.dart';

abstract interface class AttachmentTransferStore {
  Future<List<AttachmentTransferState>> readAll();

  Future<void> writeAll(Iterable<AttachmentTransferState> transfers);
}

class SharedPreferencesAttachmentTransferStore
    implements AttachmentTransferStore {
  static const _storageKey = 'pqc.attachment_transfers.v1';

  @override
  Future<List<AttachmentTransferState>> readAll() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => AttachmentTransferState.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.localId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> writeAll(Iterable<AttachmentTransferState> transfers) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(transfers.map((item) => item.toJson()).toList()),
    );
  }
}
