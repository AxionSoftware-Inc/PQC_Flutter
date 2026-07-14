from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0014_recovery_audit_hash_chain'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.AddField(model_name='accountkeysetescrowrecord', name='state', field=models.CharField(default='active', max_length=32)),
        migrations.AddField(model_name='accountkeysetescrowrecord', name='revoked_at', field=models.DateTimeField(blank=True, null=True)),
        migrations.CreateModel(
            name='RecoveryDeviceApproval',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('requester_device_id', models.CharField(max_length=255)),
                ('approver_device_id', models.CharField(blank=True, max_length=255)),
                ('status', models.CharField(choices=[('pending', 'Pending'), ('approved', 'Approved'), ('denied', 'Denied'), ('expired', 'Expired')], default='pending', max_length=16)),
                ('challenge', models.CharField(max_length=128, unique=True)),
                ('expires_at', models.DateTimeField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('approved_at', models.DateTimeField(blank=True, null=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, to=settings.AUTH_USER_MODEL)),
            ],
        ),
    ]
