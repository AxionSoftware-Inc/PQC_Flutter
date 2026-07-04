from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0002_userdevice_identity_public_key_and_more'),
        ('chat', '0001_initial'),
    ]

    operations = [
        migrations.CreateModel(
            name='ConversationKeyEnvelope',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('key_id', models.CharField(max_length=64)),
                ('algorithm', models.CharField(max_length=64)),
                ('wrapped_key', models.TextField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('conversation', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='key_envelopes', to='chat.conversation')),
                ('sender_device', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='sent_conversation_key_envelopes', to='users.userdevice')),
                ('target_device', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='conversation_key_envelopes', to='users.userdevice')),
            ],
            options={
                'ordering': ['-updated_at', '-id'],
                'unique_together': {('conversation', 'target_device', 'key_id')},
            },
        ),
    ]
