from django.utils import timezone
from rest_framework import serializers

from .models import KpiGoal, TaskAttachment, WorkTask


class TaskAttachmentSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()
    class Meta:
        model = TaskAttachment
        fields = ['id', 'filename', 'size_bytes', 'url', 'created_at']
    def get_url(self, obj):
        return obj.file.url


class WorkTaskSerializer(serializers.ModelSerializer):
    assignee_id = serializers.IntegerField(required=False, allow_null=True, write_only=True)
    assignee_name = serializers.SerializerMethodField()
    attachments = TaskAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = WorkTask
        fields = ['id', 'title', 'description', 'status', 'priority', 'assignee_id', 'assignee_name', 'due_at', 'completion_note', 'review_note', 'submitted_at', 'reviewed_at', 'completed_at', 'attachments', 'created_at', 'updated_at']
        read_only_fields = ['completed_at', 'submitted_at', 'reviewed_at', 'created_at', 'updated_at']

    def get_assignee_name(self, obj):
        if not obj.assignee_id:
            return ''
        user = obj.assignee.organization_member.user
        return user.first_name or user.username

    def validate_assignee_id(self, value):
        if value is None:
            return value
        workspace = self.context['workspace']
        if not workspace.members.filter(id=value, is_active=True, organization_member__is_active=True).exists():
            raise serializers.ValidationError('Active workspace member not found.')
        return value

    def update(self, instance, validated_data):
        assignee_id = validated_data.pop('assignee_id', serializers.empty)
        if assignee_id is not serializers.empty:
            instance.assignee_id = assignee_id
        previous = instance.status
        for key, value in validated_data.items():
            setattr(instance, key, value)
        if instance.status == WorkTask.Status.DONE and previous != WorkTask.Status.DONE:
            instance.completed_at = timezone.now()
        elif instance.status != WorkTask.Status.DONE:
            instance.completed_at = None
        instance.save()
        return instance


class KpiGoalSerializer(serializers.ModelSerializer):
    owner_id = serializers.IntegerField(write_only=True)
    owner_name = serializers.SerializerMethodField()
    progress = serializers.SerializerMethodField()

    class Meta:
        model = KpiGoal
        fields = ['id', 'title', 'unit', 'target_value', 'current_value', 'progress', 'owner_id', 'owner_name', 'period_start', 'period_end', 'is_active']

    def get_owner_name(self, obj):
        user = obj.owner.organization_member.user
        return user.first_name or user.username

    def get_progress(self, obj):
        if not obj.target_value:
            return 0
        return min(100, round(float(obj.current_value / obj.target_value * 100), 1))

    def validate_owner_id(self, value):
        workspace = self.context['workspace']
        if not workspace.members.filter(id=value, is_active=True, organization_member__is_active=True).exists():
            raise serializers.ValidationError('Active workspace member not found.')
        return value
