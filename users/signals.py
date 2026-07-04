from django.apps import apps
from django.db.models.signals import post_migrate
from django.dispatch import receiver


@receiver(post_migrate)
def seed_demo_data(sender, **kwargs):
    if sender.name != 'users':
        return

    Conversation = apps.get_model('chat', 'Conversation')

    Conversation.objects.get_or_create(
        type=Conversation.ConversationType.GROUP,
        title='General Group',
    )
