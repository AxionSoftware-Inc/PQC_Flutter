from django.apps import apps
from django.db.models.signals import post_migrate
from django.dispatch import receiver


@receiver(post_migrate)
def seed_demo_data(sender, **kwargs):
    if sender.name != 'users':
        return

    Conversation = apps.get_model('chat', 'Conversation')
    Organization = apps.get_model('users', 'Organization')
    Workspace = apps.get_model('users', 'Workspace')

    org, _ = Organization.objects.get_or_create(
        slug='default-org',
        defaults={
            'name': 'Default Organization',
        },
    )
    workspace, _ = Workspace.objects.get_or_create(
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

    Conversation.objects.get_or_create(
        type=Conversation.ConversationType.GROUP,
        title='General Group',
        workspace=workspace,
    )
