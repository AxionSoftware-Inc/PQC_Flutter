from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0011_historicaldevicekey'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='AccountRecoveryManifest',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('schema_version', models.PositiveIntegerField(default=2)),
                ('encrypted_payload', models.TextField()),
                ('kms_key_id', models.CharField(max_length=512)),
                ('kms_key_version', models.CharField(max_length=512)),
                ('payload_sha256', models.CharField(max_length=64)),
                ('sequence', models.PositiveBigIntegerField(default=1)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='account_recovery_manifest', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.CreateModel(
            name='CryptoRecoveryAuditEvent',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('event_type', models.CharField(max_length=64)),
                ('device_id', models.CharField(blank=True, max_length=255)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
            options={'ordering': ['id']},
        ),
        migrations.DeleteModel(name='AccountKeyVault'),
    ]
