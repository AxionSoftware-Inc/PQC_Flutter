from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0012_pqcv2_recovery_manifest'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(
            model_name='accountrecoverymanifest',
            name='vector_clock',
            field=models.JSONField(blank=True, default=dict),
        ),
        migrations.AddField(
            model_name='accountrecoverymanifest',
            name='merkle_root',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.CreateModel(
            name='AccountKeysetEscrowRecord',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('source_device_id', models.CharField(max_length=255)),
                ('keyset_id', models.CharField(blank=True, max_length=255)),
                ('epoch_id', models.CharField(blank=True, max_length=255)),
                ('record_type', models.CharField(default='device_snapshot', max_length=64)),
                ('encrypted_data_key', models.TextField()),
                ('ciphertext', models.TextField()),
                ('nonce', models.CharField(max_length=64)),
                ('kms_key_id', models.CharField(max_length=512)),
                ('encryption_context', models.JSONField(default=dict)),
                ('payload_sha256', models.CharField(max_length=64)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
            options={'ordering': ['id']},
        ),
        migrations.AddConstraint(
            model_name='accountkeysetescrowrecord',
            constraint=models.UniqueConstraint(fields=('user', 'source_device_id', 'payload_sha256'), name='users_escrow_record_content_unique'),
        ),
    ]
