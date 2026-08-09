from django.utils import timezone
from rest_framework import serializers

from .models import KpiGoal, KpiGoalHistory, TaskActivity, TaskAttachment, TaskNotification, WorkTask
from .permissions import can_comment_on_task, can_manage_task, can_view_task
from .workflow import available_actions


class TaskAttachmentSerializer(serializers.ModelSerializer):
    url = serializers.SerializerMethodField()
    class Meta:
        model = TaskAttachment
        fields = ['id', 'filename', 'size_bytes', 'url', 'created_at']
    def get_url(self, obj):
        # Do not expose storage URLs: the download endpoint checks the task
        # participant again for every request.
        return f'/task-kpi/attachments/{obj.id}/download'


class TaskActivitySerializer(serializers.ModelSerializer):
    author_name = serializers.SerializerMethodField()
    attachments = TaskAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = TaskActivity
        fields = ['id', 'kind', 'body', 'metadata', 'author_name', 'attachments', 'created_at']

    def get_author_name(self, obj):
        if not obj.created_by_id:
            return 'Tizim'
        return obj.created_by.first_name or obj.created_by.username


class TaskNotificationSerializer(serializers.ModelSerializer):
    task_id = serializers.IntegerField(source='task.id', read_only=True)
    task_title = serializers.CharField(source='task.title', read_only=True)
    activity = TaskActivitySerializer(read_only=True)

    class Meta:
        model = TaskNotification
        fields = ['id', 'task_id', 'task_title', 'kind', 'activity', 'read_at', 'created_at']


class WorkTaskSerializer(serializers.ModelSerializer):
    assignee_id = serializers.IntegerField(required=False, allow_null=True)
    assignee_name = serializers.SerializerMethodField()
    attachments = TaskAttachmentSerializer(many=True, read_only=True)
    available_actions = serializers.SerializerMethodField()
    permissions = serializers.SerializerMethodField()
    watcher_ids = serializers.SerializerMethodField()

    class Meta:
        model = WorkTask
        fields = ['id', 'title', 'description', 'status', 'priority', 'assignee_id', 'assignee_name', 'watcher_ids', 'due_at', 'started_at', 'completion_note', 'review_note', 'submitted_at', 'reviewed_at', 'completed_at', 'cancelled_at', 'cancellation_note', 'attachments', 'available_actions', 'permissions', 'created_at', 'updated_at']
        read_only_fields = ['completed_at', 'submitted_at', 'reviewed_at', 'created_at', 'updated_at']

    def get_assignee_name(self, obj):
        if not obj.assignee_id:
            return ''
        user = obj.assignee.organization_member.user
        return user.first_name or user.username

    def get_available_actions(self, obj):
        member = self.context.get('actor_member')
        if not member:
            return []
        return list(available_actions(
            obj,
            member,
            can_manage=can_manage_task(obj, member, self.context['assignable_members']),
        ))

    def get_permissions(self, obj):
        member = self.context.get('actor_member')
        if not member:
            return {}
        assignable_members = self.context['assignable_members']
        return {
            'can_view': can_view_task(obj, member, assignable_members),
            'can_comment': can_comment_on_task(obj, member, assignable_members),
            'can_manage': can_manage_task(obj, member, assignable_members),
            'is_assignee': obj.assignee_id == member.id,
            'is_watcher': obj.watchers.filter(member_id=member.id).exists(),
        }

    def get_watcher_ids(self, obj):
        return list(obj.watchers.values_list('member_id', flat=True))

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


class KpiGoalHistorySerializer(serializers.ModelSerializer):
    class Meta:
        model = KpiGoalHistory
        fields = ['id', 'target_value', 'current_value', 'period_start', 'period_end', 'created_at']
