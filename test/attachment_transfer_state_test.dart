import 'package:chat_core/chat_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('attachment transfer state persists pause and resume transitions', () async {
    final store = _MemoryTransferStore();
    final remote = ChatRemoteDataSource(apiClient: ApiClient());
    final facade = AttachmentTransferFacade(
      remoteDataSource: remote,
      store: store,
    );

    await facade.beginUpload(
      localId: 'message-1:attachment:0',
      conversationId: 7,
      filename: 'photo.bin',
      totalChunks: 3,
    );
    await facade.updateUploadProgress(
      localId: 'message-1:attachment:0',
      completedChunks: 1,
      totalChunks: 3,
    );
    await facade.pauseTransfer('message-1:attachment:0');
    expect(
      facade.transfers.value.single.status,
      AttachmentTransferStatus.paused,
    );

    final reloaded = AttachmentTransferFacade(
      remoteDataSource: remote,
      store: store,
    );
    final recovered = await reloaded.loadTransfers();
    expect(recovered.single.progress.completedChunks, 1);
    expect(recovered.single.status, AttachmentTransferStatus.paused);

    final resumed = await reloaded.resumeTransfer('message-1:attachment:0');
    expect(resumed?.status, AttachmentTransferStatus.queued);
    await reloaded.completeUpload('message-1:attachment:0', attachmentId: 55);
    expect(
      reloaded.transfers.value.single.status,
      AttachmentTransferStatus.completed,
    );
  });
}

class _MemoryTransferStore implements AttachmentTransferStore {
  List<AttachmentTransferState> values = const [];

  @override
  Future<List<AttachmentTransferState>> readAll() async => values;

  @override
  Future<void> writeAll(Iterable<AttachmentTransferState> transfers) async {
    values = List<AttachmentTransferState>.of(transfers);
  }
}
