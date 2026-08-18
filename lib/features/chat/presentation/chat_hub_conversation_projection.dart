part of 'chat_hub_controller.dart';

// Projection members implement the contract declared by the base controller.
// ignore_for_file: annotate_overrides

mixin _ChatHubConversationProjection on _ChatHubControllerBase {
  WorkspaceSummary? _findCurrentWorkspace(SessionUser sessionUser) {
    for (final organization in sessionUser.organizations) {
      for (final workspace in organization.workspaces) {
        if (workspace.id == sessionUser.activeWorkspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }

  Conversation? _findPrivateConversation(int otherUserId) {
    for (final conversation in _conversations) {
      if (conversation.isGroup) {
        continue;
      }
      if (conversation.participantIds.contains(otherUserId)) {
        return conversation;
      }
    }
    return null;
  }

  MessageDeliveryState _deliveryStateFromStored(String value) {
    switch (value) {
      case 'pending':
        return MessageDeliveryState.pending;
      case 'failed-retryable':
        return MessageDeliveryState.failedRetryable;
      case 'failed-permanent':
        return MessageDeliveryState.failedPermanent;
      case 'sent':
      default:
        return MessageDeliveryState.sent;
    }
  }

  int _trustPriority(ContactTrustBadgeState badge) {
    switch (badge.tone) {
      case UiStatusTone.success:
        return 0;
      case UiStatusTone.info:
        return 1;
      case UiStatusTone.warning:
        return 2;
      case UiStatusTone.danger:
        return 3;
    }
  }
}
