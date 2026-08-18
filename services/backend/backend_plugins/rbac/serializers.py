from rest_framework import serializers

from .models import JobRole, JobRoleAssignment


class JobRoleSerializer(serializers.ModelSerializer):
    class Meta:
        model = JobRole
        fields = ['id', 'name', 'rank', 'visibility', 'is_active']


class JobRoleAssignmentSerializer(serializers.ModelSerializer):
    member_id = serializers.IntegerField(source='workspace_member_id')
    user_id = serializers.IntegerField(source='workspace_member.organization_member.user_id')
    display_name = serializers.SerializerMethodField()
    email = serializers.SerializerMethodField()
    system_role = serializers.CharField(source='workspace_member.role')
    is_active = serializers.BooleanField(source='workspace_member.is_active')
    role = JobRoleSerializer(read_only=True)

    class Meta:
        model = JobRoleAssignment
        fields = ['member_id', 'user_id', 'display_name', 'email', 'system_role', 'is_active', 'role', 'updated_at']

    def get_display_name(self, obj):
        user = obj.workspace_member.organization_member.user
        return user.first_name or user.username

    def get_email(self, obj):
        user = obj.workspace_member.organization_member.user
        return getattr(getattr(user, 'google_account', None), 'email', '') or getattr(user, 'email', '')


class AssignmentWriteSerializer(serializers.Serializer):
    role_id = serializers.IntegerField(required=False, allow_null=True)


class InvitationWriteSerializer(serializers.Serializer):
    email = serializers.EmailField()
