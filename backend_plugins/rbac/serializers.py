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
    role = JobRoleSerializer(read_only=True)

    class Meta:
        model = JobRoleAssignment
        fields = ['member_id', 'user_id', 'display_name', 'role', 'updated_at']

    def get_display_name(self, obj):
        user = obj.workspace_member.organization_member.user
        return user.first_name or user.username


class AssignmentWriteSerializer(serializers.Serializer):
    role_id = serializers.IntegerField(required=False, allow_null=True)
