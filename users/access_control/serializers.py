from rest_framework import serializers

from users.access_control.catalog import PERMISSIONS_BY_CODE
from users.models import (
    WorkspaceAccessRole,
    WorkspaceAccessRoleAssignment,
    WorkspaceAccessRolePermission,
)


class WorkspaceAccessRoleSerializer(serializers.ModelSerializer):
    permissions = serializers.SerializerMethodField()

    class Meta:
        model = WorkspaceAccessRole
        fields = (
            'id',
            'workspace_id',
            'key',
            'name',
            'description',
            'is_active',
            'permissions',
            'created_at',
            'updated_at',
        )

    def get_permissions(self, obj):
        return [
            item.permission_code
            for item in obj.permissions.all().order_by('permission_code')
        ]


class WorkspaceAccessRoleWriteSerializer(serializers.Serializer):
    key = serializers.SlugField(max_length=64)
    name = serializers.CharField(max_length=120)
    description = serializers.CharField(
        max_length=255,
        required=False,
        allow_blank=True,
    )
    is_active = serializers.BooleanField(required=False)
    permissions = serializers.ListField(
        child=serializers.CharField(max_length=96),
        allow_empty=True,
    )

    def validate_permissions(self, value):
        unknown = sorted(set(value) - set(PERMISSIONS_BY_CODE))
        if unknown:
            raise serializers.ValidationError(
                f'Unknown permission codes: {", ".join(unknown)}'
            )
        return sorted(set(value))

    def apply_to(self, *, role):
        for field in ('key', 'name', 'description', 'is_active'):
            if field in self.validated_data:
                setattr(role, field, self.validated_data[field])
        role.save()
        if 'permissions' in self.validated_data:
            role.permissions.all().delete()
            WorkspaceAccessRolePermission.objects.bulk_create(
                [
                    WorkspaceAccessRolePermission(
                        role=role,
                        permission_code=permission_code,
                    )
                    for permission_code in self.validated_data['permissions']
                ]
            )
        return role


class WorkspaceAccessRoleAssignmentSerializer(serializers.ModelSerializer):
    role_key = serializers.CharField(source='role.key', read_only=True)
    role_name = serializers.CharField(source='role.name', read_only=True)
    user_id = serializers.IntegerField(
        source='workspace_member.organization_member.user_id',
        read_only=True,
    )

    class Meta:
        model = WorkspaceAccessRoleAssignment
        fields = (
            'id',
            'workspace_member_id',
            'user_id',
            'role_id',
            'role_key',
            'role_name',
            'created_at',
        )


class WorkspaceAccessRoleAssignmentWriteSerializer(serializers.Serializer):
    workspace_member_id = serializers.IntegerField(min_value=1)
    role_id = serializers.IntegerField(min_value=1)
