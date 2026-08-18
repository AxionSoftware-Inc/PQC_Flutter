from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [('chat', '0005_messageattachment_chunk_size_and_more')]

    operations = [
        migrations.CreateModel(
            name='ConversationCryptoEpoch',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('epoch_id', models.CharField(max_length=64, unique=True)),
                ('state', models.CharField(choices=[('pending', 'Pending'), ('active', 'Active'), ('closed', 'Closed')], default='pending', max_length=16)),
                ('reason', models.CharField(blank=True, max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('activated_at', models.DateTimeField(blank=True, null=True)),
                ('conversation', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='crypto_epochs', to='chat.conversation')),
            ],
            options={'ordering': ['-id']},
        ),
    ]
