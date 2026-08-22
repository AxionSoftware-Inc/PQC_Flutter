part of 'chat_page.dart';

// ignore_for_file: invalid_use_of_protected_member

extension _ChatPageMessageViews on _ChatPageState {
  Widget _buildPage(BuildContext context) {
    final conversationTrust = _controller.trust?.trust;
    final spacing = context.appSpacing;
    final colors = context.appColors;
    final brand = AppBrandScope.of(context).brand;
    final needsBackupRestore = _controller.messages.any(
      (item) =>
          item.body == ChatCryptoService.decryptNeedsBackupRestoreMarker ||
          item.body == ChatCryptoService.decryptKeyMissingMarker,
    );
    return AppScaffold(
      appBar: AppBar(toolbarHeight: 0),
      body: Column(
        children: [
          _ConversationHeader(
            title: widget.title,
            avatarUrl: widget.avatarUrl,
            roleLabel: widget.roleLabel,
            conversation: widget.conversation,
            trust: conversationTrust,
            brandLabel: brand?.label,
            onBack: () => Navigator.of(context).maybePop(),
            onOpenDetails: _showConversationDetails,
            onVerify:
                !widget.conversation.isGroup &&
                    conversationTrust?.isAvailable == true
                ? _verifyCurrentKey
                : null,
            transferCount: _visibleAttachmentTransfers.length,
          ),
          if (_controller.isLoading) const LinearProgressIndicator(),
          if (_controller.error != null)
            Padding(
              padding: EdgeInsets.all(spacing.sm),
              child: AppStatusBanner(
                message: _controller.error!,
                tone: AppStatusTone.danger,
              ),
            ),
          if (!widget.conversation.isGroup && conversationTrust != null)
            Column(
              children: [
                _SecurityBanner(
                  trust: conversationTrust,
                  onVerify: _verifyCurrentKey,
                  isExpanded: _showSecurityDetails,
                  onToggleExpanded: () {
                    setState(() {
                      _showSecurityDetails = !_showSecurityDetails;
                    });
                  },
                ),
                if (_showSecurityDetails)
                  _SecurityDetailCard(trust: conversationTrust),
              ],
            ),
          if (needsBackupRestore)
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.sm,
                spacing.sm,
                0,
              ),
              child: const AppStatusBanner(
                message:
                    'Ba’zi eski xabarlarni ochish uchun tiklash talab qilinadi. Sozlamalar > Zaxira va tiklash bo‘limidan foydalaning.',
                tone: AppStatusTone.warning,
              ),
            ),
          Expanded(
            child: _controller.isLoading && _controller.messages.isEmpty
                ? _buildLoadingState()
                : _controller.messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: AppEmptyState(
                        message: context.antiQText(
                          uz: 'Suhbat hali bo‘sh. Birinchi xabarni yuboring.',
                          en: 'This conversation is empty. Send the first message.',
                        ),
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    ),
                  )
                : ChatThreadWidget(
                    controller: _scrollController,
                    padding: EdgeInsets.fromLTRB(
                      spacing.sm,
                      spacing.sm,
                      spacing.sm,
                      spacing.xs,
                    ),
                    messages: _controller.messages
                        .map(_toThreadMessage)
                        .toList(),
                    currentUserId: widget.currentUserId,
                    isGroup: widget.conversation.isGroup,
                    attachmentBuilder:
                        (
                          context,
                          attachment, {
                          required message,
                          required showDeliveryOverlay,
                        }) {
                          final raw = attachment.raw as ChatAttachment;
                          return _buildAttachmentChip(
                            raw,
                            message: message.raw as ChatMessage,
                            isMine: message.isMine,
                            showDeliveryOverlay: showDeliveryOverlay,
                          );
                        },
                    footerBuilder: (context, message) => _buildMessageFooter(
                      message: message.raw as ChatMessage,
                      isMine: message.isMine,
                    ),
                    bodyLabelBuilder: (message) {
                      final body = message.body;
                      if (body ==
                              ChatCryptoService
                                  .decryptNeedsBackupRestoreMarker ||
                          body == ChatCryptoService.decryptKeyMissingMarker) {
                        return 'Bu qurilmada eski xabar kaliti topilmadi. Zaxira nusxasini tiklang.';
                      }
                      if (body == ChatCryptoService.decryptErrorMarker) {
                        return 'Bu xabarni shifrdan chiqarib bo‘lmadi.';
                      }
                      return body;
                    },
                    onRetry: (message) =>
                        _retryMessage(message.raw as ChatMessage),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.sm,
                spacing.xs,
                spacing.sm,
                spacing.sm,
              ),
              child: Column(
                children: [
                  if (_visibleAttachmentTransfers.isNotEmpty)
                    _buildTransferSection(
                      expanded: _showTransferDetails,
                      onToggleExpanded: () {
                        setState(() {
                          _showTransferDetails = !_showTransferDetails;
                        });
                      },
                    ),
                  if (_visibleAttachmentTransfers.isNotEmpty)
                    SizedBox(height: spacing.sm),
                  if (_selectedAttachments.isNotEmpty)
                    _buildSelectedAttachmentTray(),
                  if (_selectedAttachments.isNotEmpty)
                    SizedBox(height: spacing.xs),
                  AnimatedContainer(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.xs + 2,
                      vertical: spacing.xs + 2,
                    ),
                    decoration: BoxDecoration(
                      color: _composerFocusNode.hasFocus
                          ? Color.lerp(colors.surface, colors.primarySoft, 0.18)
                          : colors.surface.withValues(alpha: 0.98),
                      borderRadius: BorderRadius.circular(context.appRadii.xl),
                      border: Border.all(
                        color: _composerFocusNode.hasFocus
                            ? colors.primary.withValues(alpha: 0.72)
                            : colors.border.withValues(alpha: 0.72),
                      ),
                      boxShadow: _composerFocusNode.hasFocus
                          ? [
                              BoxShadow(
                                color: colors.primary.withValues(alpha: 0.14),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : context.appShadows.floating,
                    ),
                    duration: context.appDurations.fast,
                    curve: Curves.easeOutCubic,
                    child: AnimatedSize(
                      duration: context.appDurations.fast,
                      curve: Curves.easeOutCubic,
                      child: Row(
                        children: [
                          _ComposerActionButton(
                            icon: Icons.add_rounded,
                            onPressed: _controller.isSending
                                ? null
                                : _pickAttachments,
                          ),
                          Expanded(
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                inputDecorationTheme: Theme.of(context)
                                    .inputDecorationTheme
                                    .copyWith(
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: spacing.sm,
                                        vertical: spacing.xs,
                                      ),
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      border: InputBorder.none,
                                    ),
                              ),
                              child: AppTextField(
                                controller: _messageController,
                                focusNode: _composerFocusNode,
                                hintText: context.antiQText(
                                  uz: 'Xabar',
                                  en: 'Message',
                                ),
                                maxLines: 4,
                                minLines: 1,
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          SizedBox(width: spacing.xs),
                          _ComposerSendButton(
                            isSending: _controller.isSending,
                            onPressed: _controller.isSending
                                ? null
                                : _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
