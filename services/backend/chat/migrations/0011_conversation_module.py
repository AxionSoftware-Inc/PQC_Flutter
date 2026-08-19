from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('chat', '0010_message_actions_reactions'),
    ]

    operations = [
        migrations.AddField(
            model_name='conversation',
            name='module',
            field=models.CharField(
                choices=[('chat', 'Chat'), ('kpi', 'KPI')],
                default='chat',
                max_length=32,
            ),
        ),
        migrations.AddField(
            model_name='conversation',
            name='module_key',
            field=models.CharField(blank=True, default='', max_length=128),
        ),
        migrations.AddConstraint(
            model_name='conversation',
            constraint=models.UniqueConstraint(
                condition=~models.Q(module_key=''),
                fields=('workspace', 'module', 'module_key'),
                name='chat_conversation_unique_module_key',
            ),
        ),
    ]
