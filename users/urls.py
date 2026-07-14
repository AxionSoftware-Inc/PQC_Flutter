from django.urls import path

from users.views import (
    DeviceListView,
    DeviceRevokeView,
    DeviceSyncView,
    InvitationAcceptView,
    InvitationListCreateView,
    LoginView,
    GoogleLoginView,
    MeView,
    CryptoBackupView,
    AccountRecoveryManifestView,
    CryptoObservabilityView,
    RecoveryApprovalRequestView,
    RecoveryApprovalDecisionView,
    OrganizationListView,
    UserListView,
    WorkspaceMemberDeactivateView,
    WorkspaceSwitchView,
)


urlpatterns = [
    path('auth/login', LoginView.as_view(), name='login'),
    path('auth/google', GoogleLoginView.as_view(), name='google-login'),
    path('users', UserListView.as_view(), name='users'),
    path('users/me', MeView.as_view(), name='me'),
    path('users/me/crypto-backup', CryptoBackupView.as_view(), name='crypto-backup'),
    path('users/me/crypto-recovery', AccountRecoveryManifestView.as_view(), name='crypto-recovery'),
    path('users/me/crypto-observability', CryptoObservabilityView.as_view(), name='crypto-observability'),
    path('users/me/crypto-recovery/approvals', RecoveryApprovalRequestView.as_view(), name='crypto-recovery-approvals'),
    path('users/me/crypto-recovery/approvals/<int:approval_id>', RecoveryApprovalDecisionView.as_view(), name='crypto-recovery-approval-decision'),
    path('users/me/workspace', WorkspaceSwitchView.as_view(), name='workspace-switch'),
    path('users/me/device', DeviceSyncView.as_view(), name='device-sync'),
    path('users/me/device/sync', DeviceSyncView.as_view(), name='device-sync-v2'),
    path('users/me/devices', DeviceListView.as_view(), name='device-list'),
    path('users/me/devices/<str:device_id>/revoke', DeviceRevokeView.as_view(), name='device-revoke'),
    path('organizations', OrganizationListView.as_view(), name='organizations'),
    path('invitations', InvitationListCreateView.as_view(), name='invitations'),
    path('invitations/accept', InvitationAcceptView.as_view(), name='invite-accept'),
    path(
        'workspace-members/<int:member_id>/deactivate',
        WorkspaceMemberDeactivateView.as_view(),
        name='workspace-member-deactivate',
    ),
]
