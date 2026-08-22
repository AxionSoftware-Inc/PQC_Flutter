part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageStateActions on _ChatPageState {
  Future<void> _initialize() async {
    try {
      await _loadDraftPreferences();
      await _controller.initialize();
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
        return;
      }
      // The controller keeps the existing/local history and exposes the
      // failure in its status banner. Do not let the unawaited initialization
      // escape as a framework error and cause the page to restart.
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _loadDraftPreferences() async {
    final preferences = await _preferencesStore.readAppPreferences();
    _keepDrafts = preferences.keepDrafts;
    if (!_keepDrafts) {
      return;
    }
    final existing = await widget.database.readDraft(widget.conversation.id);
    if (existing == null || existing.draftText.trim().isEmpty) {
      return;
    }
    _messageController.text = existing.draftText;
  }

  void _onControllerChanged() {
    if (!mounted) {
      return;
    }
    final messageCount = _controller.messages.length;
    final isNearBottom =
        !_scrollController.hasClients ||
        _scrollController.position.maxScrollExtent -
                _scrollController.position.pixels <
            96;
    final shouldJump =
        !_hasRenderedMessages ||
        (messageCount > _lastMessageCount && isNearBottom);
    _lastMessageCount = messageCount;
    _hasRenderedMessages = true;
    for (final transfer in _controller.attachmentTransfers) {
      if (transfer.attachmentId != null && transfer.localPath != null) {
        _downloadedAttachmentPaths[transfer.attachmentId!] =
            transfer.localPath!;
      }
    }
    setState(() {});
    _queueMissingImagePreviews();
    if (shouldJump) {
      _jumpToBottom();
    }
  }

  void _queueMissingImagePreviews() {
    if (_isImagePreviewQueueRunning) {
      return;
    }
    _isImagePreviewQueueRunning = true;
    unawaited(_drainImagePreviewQueue());
  }

  Future<void> _drainImagePreviewQueue() async {
    final recentImages = _controller.messages.reversed
        .expand((message) => message.attachments)
        .where((attachment) => attachment.mimeType.startsWith('image/'))
        .take(24);
    try {
      for (final attachment in recentImages) {
        if (_downloadedAttachmentPaths.containsKey(attachment.id) ||
            _imagePreviewDownloadFailures.contains(attachment.id) ||
            !_imagePreviewDownloadsInFlight.add(attachment.id)) {
          continue;
        }
        await _downloadImagePreview(attachment);
      }
    } finally {
      _isImagePreviewQueueRunning = false;
    }
  }

  Future<void> _downloadImagePreview(ChatAttachment attachment) async {
    try {
      final path = await _controller.downloadAttachment(attachment);
      if (!mounted) {
        return;
      }
      setState(() {
        _downloadedAttachmentPaths[attachment.id] = path;
      });
    } catch (_) {
      _imagePreviewDownloadFailures.add(attachment.id);
      // Preview loading is best-effort. Tapping the placeholder retries and
      // surfaces the actual download error to the user.
    } finally {
      _imagePreviewDownloadsInFlight.remove(attachment.id);
    }
  }

  List<AttachmentTransferState> get _visibleAttachmentTransfers => _controller
      .attachmentTransfers
      .where((item) => item.status != AttachmentTransferStatus.completed)
      .toList(growable: false);

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _selectedAttachments.isEmpty) ||
        _controller.isSending) {
      return;
    }

    final command = SendMessageCommand(
      conversation: widget.conversation,
      currentUserId: widget.currentUserId,
      text: text,
      messageType: _selectedAttachments.isEmpty
          ? 'text'
          : _selectedAttachments.any((item) => item.isImage)
          ? 'image'
          : 'file',
      attachments: _selectedAttachments
          .map(
            (item) => PendingAttachmentUpload(
              filename: item.name,
              bytes: item.bytes,
              filePath: item.filePath,
              sizeBytes: item.sizeBytes,
              mimeType: item.mimeType,
            ),
          )
          .toList(),
    );
    // Clear the composer immediately. The controller already renders a
    // durable pending bubble, so the UI never feels blocked by encryption or
    // a slow server round trip.
    _messageController.clear();
    setState(() => _selectedAttachments = const []);
    unawaited(
      widget.database
          .upsertDraft(
            DraftsTableCompanion(
              conversationId: drift.Value(widget.conversation.id),
              draftText: const drift.Value(''),
              updatedAt: drift.Value(DateTime.now().toUtc()),
            ),
          )
          .catchError((_) {}),
    );

    try {
      await _controller.sendMessage(command);
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
        return;
      }
      if (!mounted) {
        return;
      }
      final message = error is ChatEncryptionException
          ? error.message
          : error.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
    );
    if (result == null || !mounted) {
      return;
    }
    final picked = <_SelectedAttachment>[];
    for (final file in result.files) {
      if (file.size <= 0) {
        continue;
      }
      if (file.size > TransferPolicy.maxAttachmentBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${file.name} juda katta. Har bir fayl uchun limit: ${TransferPolicy.formatBytes(TransferPolicy.maxAttachmentBytes)}.',
            ),
          ),
        );
        continue;
      }
      final hasBytes = file.bytes != null && file.bytes!.isNotEmpty;
      final hasPath = file.path != null && file.path!.trim().isNotEmpty;
      if (!hasBytes && !hasPath) {
        continue;
      }
      picked.add(
        _SelectedAttachment(
          name: file.name,
          bytes: file.bytes,
          filePath: file.path,
          sizeBytes: file.size,
          mimeType: _inferMimeType(file.name),
        ),
      );
    }
    if (picked.isEmpty) {
      return;
    }
    setState(() {
      _selectedAttachments = [..._selectedAttachments, ...picked];
    });
  }

  void _removeSelectedAttachment(_SelectedAttachment attachment) {
    setState(() {
      _selectedAttachments = _selectedAttachments
          .where((item) => item != attachment)
          .toList();
    });
  }

  Future<void> _retryMessage(ChatMessage message) async {
    try {
      await _controller.retryMessage(message.clientMessageId);
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
      }
    }
  }

  Future<void> _verifyCurrentKey() async {
    try {
      await _controller.verifyCurrentKey();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Joriy kalit tasdiqlandi.')));
    } catch (error) {
      if (error is UnauthorizedApiException) {
        await widget.onUnauthorized();
      }
    }
  }

  void _queueDraftSave() {
    if (!_keepDrafts) {
      return;
    }
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 350), () async {
      await widget.database.upsertDraft(
        DraftsTableCompanion(
          conversationId: drift.Value(widget.conversation.id),
          draftText: drift.Value(_messageController.text),
          updatedAt: drift.Value(DateTime.now().toUtc()),
        ),
      );
    });
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }
}
