from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('chat', '0002_conversationkeyenvelope'),
    ]

    operations = [
        migrations.AddField(
            model_name='message',
            name='client_message_id',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddConstraint(
            model_name='message',
            constraint=models.UniqueConstraint(
                condition=models.Q(client_message_id__gt=''),
                fields=('conversation', 'sender', 'client_message_id'),
                name='chat_unique_client_message_per_sender',
            ),
        ),
    ]
