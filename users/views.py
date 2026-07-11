import hashlib

from django.contrib.auth import get_user_model
from django.db import IntegrityError, transaction
from django.utils import timezone
from django.utils.text import slugify
from uuid import uuid4

from rest_framework import permissions, status
from rest_framework.authtoken.models import Token
from rest_framework.response import Response
from rest_framework.views import APIView

from chat.models import Conversation, ConversationParticipant
from users.models import (
    Invitation,
    Organization,
    OrganizationMember,
    UserDevice,
    Workspace,
    WorkspaceMember,
)
from users.serializers import (
    DeviceSerializer,
    DeviceSyncSerializer,
    InvitationAcceptSerializer,
    InvitationCreateSerializer,
    InvitationSerializer,
    LoginSerializer,
    OrganizationSerializer,
    UserSerializer,
    WorkspaceMemberSerializer,
    WorkspaceSerializer,
    WorkspaceSwitchSerializer,
)


User = get_user_model()


def create_account_for_display_name(display_name):
    return User.objects.create(
        username=f'account_{uuid4().hex[:24]}',
        first_name=display_name,
    )


def _workspace_memberships_for_user(user):
    return WorkspaceMember.objects.select_related(
        'workspace',
        'workspace__organization',
        'organization_member',
    ).filter(
        organization_member__user=user,
        organization_member__is_active=True,
        is_active=True,
    )


def _serialize_org_context(user):
    workspace_memberships = list(_workspace_memberships_for_user(user))
    orgs = []
    roles_by_org = {}
    workspaces_by_org = {}
    seen_org_ids = set()

    for membership in workspace_memberships:
        org = membership.workspace.organization
        if org.id not in seen_org_ids:
            seen_org_ids.add(org.id)
            orgs.append(org)
        roles_by_org[org.id] = membership.organization_member.role
        workspaces_by_org.setdefault(org.id, []).append(membership.workspace)

    return OrganizationSerializer(
        orgs,
        many=True,
        context={
            'roles_by_org': roles_by_org,
            'workspace_memberships_by_org': workspaces_by_org,
        },
    ).data


def _resolve_active_workspace_for_user(user, requested_workspace_id=''):
    memberships = _workspace_memberships_for_user(user)
    if requested_workspace_id and requested_workspace_id.isdigit():
        membership = memberships.filter(workspace_id=int(requested_workspace_id)).first()
        if membership is not None:
            return membership.workspace
    default_membership = memberships.order_by('-workspace__is_default', 'workspace_id').first()
    return None if default_membership is None else default_membership.workspace


def _get_request_active_workspace(request):
    workspace = _resolve_active_workspace_for_user(
        request.user,
        request.headers.get('X-Workspace-Id', '').strip(),
    )
    if workspace is None:
        return None, Response(
            {'detail': 'Active workspace was not found for this user.'},
            status=status.HTTP_403_FORBIDDEN,
        )
    return workspace, None


def _ensure_default_workspace_membership(user):
    org, _ = _safe_get_or_create(
        Organization,
        slug='default-org',
        defaults={
            'name': 'Default Organization',
            'created_by': user,
        },
    )
    workspace, _ = _safe_get_or_create(
        Workspace,
        organization=org,
        slug='main-workspace',
        defaults={
            'name': 'Main Workspace',
            'is_default': True,
            'policy_flags': {
                'attachments_enabled': True,
                'typing_presence_enabled': True,
            },
        },
    )
    org_member, created = _safe_get_or_create(
        OrganizationMember,
        organization=org,
        user=user,
        defaults={
            'role': OrganizationMember.Role.OWNER,
        },
    )
    if not created and not org_member.is_active:
        org_member.is_active = True
        org_member.save(update_fields=['is_active', 'updated_at'])
    workspace_member, created = _safe_get_or_create(
        WorkspaceMember,
        workspace=workspace,
        organization_member=org_member,
        defaults={
            'role': org_member.role,
        },
    )
    if not created and not workspace_member.is_active:
        workspace_member.is_active = True
        workspace_member.save(update_fields=['is_active', 'updated_at'])
    return org, workspace


def _safe_get_or_create(model, defaults=None, **lookup):
    try:
        return model.objects.get_or_create(defaults=defaults or {}, **lookup)
    except IntegrityError:
        return model.objects.get(**lookup), False


def upsert_user_device(
    *,
    user,
    device_id,
    device_name='',
    platform='',
    identity_public_key='',
    key_algorithm='',
    pqc_public_key='',
    pqc_algorithm='',
    pqc_signing_public_key='',
    pqc_signing_algorithm='',
):
    profile_fingerprint = build_device_profile_fingerprint(
        device_id=device_id,
        identity_public_key=identity_public_key,
        key_algorithm=key_algorithm,
        pqc_public_key=pqc_public_key,
        pqc_algorithm=pqc_algorithm,
        pqc_signing_public_key=pqc_signing_public_key,
        pqc_signing_algorithm=pqc_signing_algorithm,
    )
    device, device_created = UserDevice.objects.get_or_create(
        device_id=device_id,
        defaults={
            'user': user,
            'device_name': device_name,
            'platform': platform,
            'identity_public_key': identity_public_key,
            'key_algorithm': key_algorithm,
            'pqc_public_key': pqc_public_key,
            'pqc_algorithm': pqc_algorithm,
            'pqc_signing_public_key': pqc_signing_public_key,
            'pqc_signing_algorithm': pqc_signing_algorithm,
            'status': UserDevice.Status.ACTIVE,
            'profile_fingerprint': profile_fingerprint,
            'last_seen_at': timezone.now(),
        },
    )
    if not device_created and device.user_id != user.id:
        return None, Response(
            {
                'detail': 'This device is already linked to another username.',
                'code': 'device_owner_mismatch',
            },
            status=status.HTTP_400_BAD_REQUEST,
        )

    if not device_created:
        if device.status != UserDevice.Status.ACTIVE:
            return None, Response(
                {
                    'detail': 'This device is no longer active.',
                    'code': 'device_revoked',
                },
                status=status.HTTP_409_CONFLICT,
            )

        if device.profile_fingerprint and device.profile_fingerprint != profile_fingerprint:
            return None, Response(
                {
                    'detail': 'This device profile does not match the registered key material.',
                    'code': 'device_profile_mismatch',
                    'device_status': device.status,
                    'profile_fingerprint': device.profile_fingerprint,
                },
                status=status.HTTP_409_CONFLICT,
            )

        updated_fields = ['last_seen_at']
        device.last_seen_at = timezone.now()
        if device.device_name != device_name:
            device.device_name = device_name
            updated_fields.append('device_name')
        if device.platform != platform:
            device.platform = platform
            updated_fields.append('platform')
        if device.identity_public_key != identity_public_key:
            device.identity_public_key = identity_public_key
            updated_fields.append('identity_public_key')
        if device.key_algorithm != key_algorithm:
            device.key_algorithm = key_algorithm
            updated_fields.append('key_algorithm')
        if device.pqc_public_key != pqc_public_key:
            device.pqc_public_key = pqc_public_key
            updated_fields.append('pqc_public_key')
        if device.pqc_algorithm != pqc_algorithm:
            device.pqc_algorithm = pqc_algorithm
            updated_fields.append('pqc_algorithm')
        if device.pqc_signing_public_key != pqc_signing_public_key:
            device.pqc_signing_public_key = pqc_signing_public_key
            updated_fields.append('pqc_signing_public_key')
        if device.pqc_signing_algorithm != pqc_signing_algorithm:
            device.pqc_signing_algorithm = pqc_signing_algorithm
            updated_fields.append('pqc_signing_algorithm')
        if not device.profile_fingerprint:
            device.profile_fingerprint = profile_fingerprint
            updated_fields.append('profile_fingerprint')
        if updated_fields:
            device.save(update_fields=updated_fields + ['updated_at'])

    return device, None


def build_device_profile_fingerprint(
    *,
    device_id,
    identity_public_key,
    key_algorithm,
    pqc_public_key,
    pqc_algorithm,
    pqc_signing_public_key,
    pqc_signing_algorithm,
):
    payload = '|'.join(
        [
            device_id,
            key_algorithm,
            identity_public_key,
            pqc_algorithm,
            pqc_public_key,
            pqc_signing_algorithm,
            pqc_signing_public_key,
        ]
    )
    return hashlib.sha256(payload.encode('utf-8')).hexdigest()
class LoginView(APIView):
    permission_classes = [permissions.AllowAny]

    @transaction.atomic
    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        display_name = ' '.join(
            serializer.validated_data['display_name'].strip().split()
        )
        device_id = serializer.validated_data['device_id'].strip()
        device_name = serializer.validated_data['device_name'].strip()
        platform = serializer.validated_data['platform'].strip()
        identity_public_key = serializer.validated_data['identity_public_key'].strip()
        key_algorithm = serializer.validated_data['key_algorithm'].strip()
        pqc_public_key = serializer.validated_data['pqc_public_key'].strip()
        pqc_algorithm = serializer.validated_data['pqc_algorithm'].strip()
        pqc_signing_public_key = serializer.validated_data['pqc_signing_public_key'].strip()
        pqc_signing_algorithm = serializer.validated_data['pqc_signing_algorithm'].strip()

        if not display_name or not device_id:
            return Response(
                {'detail': 'display_name and device_id are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        existing_device = UserDevice.objects.select_related('user').filter(
            device_id=device_id,
        ).first()
        if existing_device is not None:
            user = existing_device.user
        else:
            user = create_account_for_display_name(display_name)

        if display_name and user.first_name != display_name:
            user.first_name = display_name
            user.save(update_fields=['first_name'])

        device, error_response = upsert_user_device(
            user=user,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            identity_public_key=identity_public_key,
            key_algorithm=key_algorithm,
            pqc_public_key=pqc_public_key,
            pqc_algorithm=pqc_algorithm,
            pqc_signing_public_key=pqc_signing_public_key,
            pqc_signing_algorithm=pqc_signing_algorithm,
        )
        if error_response is not None:
            return error_response

        organization, workspace = _ensure_default_workspace_membership(user)

        group, _ = Conversation.objects.get_or_create(
            type=Conversation.ConversationType.GROUP,
            title='General Group',
            workspace=workspace,
        )
        ConversationParticipant.objects.get_or_create(
            conversation=group,
            user=user,
        )

        token, _ = Token.objects.get_or_create(user=user)
        return Response(
            {
                'token': token.key,
                'account_id': user.id,
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
                'active_workspace_id': workspace.id,
                'organizations': _serialize_org_context(user),
                'active_devices': DeviceSerializer(
                    [
                        {
                            'device_id': item.device_id,
                            'device_name': item.device_name,
                            'platform': item.platform,
                            'identity_public_key': item.identity_public_key,
                            'key_algorithm': item.key_algorithm,
                            'pqc_public_key': item.pqc_public_key,
                            'pqc_algorithm': item.pqc_algorithm,
                            'pqc_signing_public_key': item.pqc_signing_public_key,
                            'pqc_signing_algorithm': item.pqc_signing_algorithm,
                            'status': item.status,
                            'profile_fingerprint': item.profile_fingerprint,
                            'revoked_reason': item.revoked_reason,
                            'created_at': item.created_at,
                            'updated_at': item.updated_at,
                            'first_seen_at': item.first_seen_at,
                            'last_seen_at': item.last_seen_at,
                        }
                        for item in user.devices.filter(status=UserDevice.Status.ACTIVE).order_by('id')
                    ],
                    many=True,
                ).data,
                'user': UserSerializer(user).data,
            }
        )


class MeView(APIView):
    def get(self, request):
        workspace, error_response = _get_request_active_workspace(request)
        if error_response is not None:
            return error_response
        user_data = UserSerializer(request.user).data
        return Response(
            {
                **user_data,
                'active_workspace_id': workspace.id,
                'organizations': _serialize_org_context(request.user),
                'user': user_data,
            }
        )


class UserListView(APIView):
    def get(self, request):
        workspace, error_response = _get_request_active_workspace(request)
        if error_response is not None:
            return error_response
        users = User.objects.filter(
            organization_memberships__workspace_memberships__workspace=workspace,
            organization_memberships__workspace_memberships__is_active=True,
        ).distinct().order_by('id')
        return Response(UserSerializer(users, many=True).data)


class DeviceSyncView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = DeviceSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        device_id = serializer.validated_data['device_id'].strip()
        if not device_id:
            return Response(
                {'detail': 'device_id is required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        device, error_response = upsert_user_device(
            user=request.user,
            device_id=device_id,
            device_name=serializer.validated_data['device_name'].strip(),
            platform=serializer.validated_data['platform'].strip(),
            identity_public_key=serializer.validated_data['identity_public_key'].strip(),
            key_algorithm=serializer.validated_data['key_algorithm'].strip(),
            pqc_public_key=serializer.validated_data['pqc_public_key'].strip(),
            pqc_algorithm=serializer.validated_data['pqc_algorithm'].strip(),
            pqc_signing_public_key=serializer.validated_data['pqc_signing_public_key'].strip(),
            pqc_signing_algorithm=serializer.validated_data['pqc_signing_algorithm'].strip(),
        )
        if error_response is not None:
            return error_response

        return Response(
            {
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
                'identity_public_key': device.identity_public_key,
                'key_algorithm': device.key_algorithm,
                'pqc_public_key': device.pqc_public_key,
                'pqc_algorithm': device.pqc_algorithm,
                'pqc_signing_public_key': device.pqc_signing_public_key,
                'pqc_signing_algorithm': device.pqc_signing_algorithm,
                'organizations': _serialize_org_context(request.user),
            }
        )


class DeviceListView(APIView):
    def get(self, request):
        devices = request.user.devices.filter(status=UserDevice.Status.ACTIVE).order_by('id')
        return Response(
            DeviceSerializer(
                [
                    {
                        'device_id': device.device_id,
                        'device_name': device.device_name,
                        'platform': device.platform,
                        'identity_public_key': device.identity_public_key,
                        'key_algorithm': device.key_algorithm,
                        'pqc_public_key': device.pqc_public_key,
                        'pqc_algorithm': device.pqc_algorithm,
                        'pqc_signing_public_key': device.pqc_signing_public_key,
                        'pqc_signing_algorithm': device.pqc_signing_algorithm,
                        'status': device.status,
                        'profile_fingerprint': device.profile_fingerprint,
                        'revoked_reason': device.revoked_reason,
                        'created_at': device.created_at,
                        'updated_at': device.updated_at,
                        'first_seen_at': device.first_seen_at,
                        'last_seen_at': device.last_seen_at,
                    }
                    for device in devices
                ],
                many=True,
            ).data
        )


class DeviceRevokeView(APIView):
    @transaction.atomic
    def post(self, request, device_id):
        device = UserDevice.objects.filter(
            user=request.user,
            device_id=device_id,
        ).first()
        if device is None:
            return Response(
                {'detail': 'Device not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        if device.status == UserDevice.Status.REVOKED:
            return Response(
                {
                    'device_id': device.device_id,
                    'device_status': device.status,
                    'profile_fingerprint': device.profile_fingerprint,
                }
            )
        device.status = UserDevice.Status.REVOKED
        device.revoked_reason = 'revoked_by_user'
        device.last_seen_at = timezone.now()
        device.save(update_fields=['status', 'revoked_reason', 'last_seen_at', 'updated_at'])
        return Response(
            {
                'device_id': device.device_id,
                'device_status': device.status,
                'profile_fingerprint': device.profile_fingerprint,
            }
        )


class OrganizationListView(APIView):
    def get(self, request):
        return Response(_serialize_org_context(request.user))


class WorkspaceSwitchView(APIView):
    def post(self, request):
        serializer = WorkspaceSwitchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        workspace = _resolve_active_workspace_for_user(
            request.user,
            str(serializer.validated_data['workspace_id']),
        )
        if workspace is None:
            return Response(
                {'detail': 'Workspace not found for this user.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        return Response(
            {
                'active_workspace_id': workspace.id,
                'workspace': WorkspaceSerializer(workspace).data,
            }
        )


class InvitationListCreateView(APIView):
    @transaction.atomic
    def get(self, request):
        invitations = Invitation.objects.filter(
            workspace__members__organization_member__user=request.user,
        ).distinct().order_by('-id')
        return Response(InvitationSerializer(invitations, many=True).data)

    @transaction.atomic
    def post(self, request):
        serializer = InvitationCreateSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        workspace = Workspace.objects.filter(
            id=serializer.validated_data['workspace_id'],
            members__organization_member__user=request.user,
            members__role__in=[
                OrganizationMember.Role.OWNER,
                OrganizationMember.Role.ADMIN,
            ],
            members__is_active=True,
        ).select_related('organization').first()
        if workspace is None:
            return Response(
                {'detail': 'Workspace not found or admin rights missing.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        invitation = Invitation.objects.create(
            organization=workspace.organization,
            workspace=workspace,
            invited_by=request.user,
            email=serializer.validated_data['email'],
            role=serializer.validated_data['role'],
            invite_code=uuid4().hex,
        )
        return Response(
            InvitationSerializer(invitation).data,
            status=status.HTTP_201_CREATED,
        )


class InvitationAcceptView(APIView):
    @transaction.atomic
    def post(self, request):
        serializer = InvitationAcceptSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        invitation = Invitation.objects.select_related(
            'organization',
            'workspace',
        ).filter(
            invite_code=serializer.validated_data['invite_code'],
            status=Invitation.Status.PENDING,
        ).first()
        if invitation is None:
            return Response(
                {'detail': 'Invitation not found or no longer active.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        org_member, _ = OrganizationMember.objects.get_or_create(
            organization=invitation.organization,
            user=request.user,
            defaults={'role': invitation.role},
        )
        if not org_member.is_active:
            org_member.is_active = True
            org_member.save(update_fields=['is_active', 'updated_at'])
        workspace_member, _ = WorkspaceMember.objects.get_or_create(
            workspace=invitation.workspace,
            organization_member=org_member,
            defaults={'role': invitation.role},
        )
        if not workspace_member.is_active:
            workspace_member.is_active = True
            workspace_member.save(update_fields=['is_active', 'updated_at'])
        invitation.status = Invitation.Status.ACCEPTED
        invitation.save(update_fields=['status', 'updated_at'])
        return Response(
            {
                'active_workspace_id': invitation.workspace_id,
                'organizations': _serialize_org_context(request.user),
            }
        )


class WorkspaceMemberDeactivateView(APIView):
    @transaction.atomic
    def post(self, request, member_id):
        membership = WorkspaceMember.objects.select_related(
            'workspace',
            'organization_member',
            'organization_member__organization',
        ).filter(id=member_id).first()
        if membership is None:
            return Response(
                {'detail': 'Workspace member not found.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        is_admin = WorkspaceMember.objects.filter(
            workspace=membership.workspace,
            organization_member__user=request.user,
            role__in=[
                OrganizationMember.Role.OWNER,
                OrganizationMember.Role.ADMIN,
            ],
            is_active=True,
        ).exists()
        if not is_admin:
            return Response(
                {'detail': 'Admin rights required.'},
                status=status.HTTP_403_FORBIDDEN,
            )
        membership.is_active = False
        membership.save(update_fields=['is_active', 'updated_at'])
        return Response(WorkspaceMemberSerializer(membership).data)
