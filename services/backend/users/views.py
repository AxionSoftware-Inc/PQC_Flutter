"""Compatibility exports for the domain-separated users API views.

Route modules and callers can keep importing from "users.views" while the
implementation remains organized by authentication, account, recovery and
device/workspace responsibilities.
"""

from urllib.request import urlopen

from users.escrow import get_key_escrow_provider

from users.api_views.account import (
    AccountSettingsView,
    CurrentUserAvatarView,
    MeView,
    UserAvatarView,
    UserBlockView,
    UserReportView,
)
from users.api_views.authentication import GoogleLoginView, LoginView
from users.api_views.common import (
    build_device_profile_fingerprint,
    create_account_for_display_name,
    upsert_user_device,
)
from users.api_views.devices import (
    DeviceListView,
    DeviceRevokeView,
    DeviceSyncView,
    InvitationAcceptView,
    InvitationListCreateView,
    OrganizationListView,
    UserListView,
    WorkspaceMemberDeactivateView,
    WorkspaceSwitchView,
)
from users.api_views.recovery import (
    AccountRecoveryManifestView,
    CryptoBackupView,
    CryptoObservabilityView,
    RecoveryApprovalDecisionView,
    RecoveryApprovalRequestView,
)
