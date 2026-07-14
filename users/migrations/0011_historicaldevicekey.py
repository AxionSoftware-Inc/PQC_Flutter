from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0010_accountkeyvault'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name='HistoricalDeviceKey',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('device_id', models.CharField(max_length=255)),
                ('identity_public_key', models.TextField(blank=True)),
                ('key_algorithm', models.CharField(blank=True, max_length=64)),
                ('pqc_public_key', models.TextField(blank=True)),
                ('pqc_algorithm', models.CharField(blank=True, max_length=64)),
                ('pqc_signing_public_key', models.TextField(blank=True)),
                ('pqc_signing_algorithm', models.CharField(blank=True, max_length=64)),
                ('profile_fingerprint', models.CharField(blank=True, max_length=128)),
                ('captured_at', models.DateTimeField(auto_now_add=True)),
                ('user', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='historical_device_keys', to=settings.AUTH_USER_MODEL)),
            ],
        ),
        migrations.AddConstraint(
            model_name='historicaldevicekey',
            constraint=models.UniqueConstraint(fields=('user', 'device_id', 'profile_fingerprint'), name='users_historical_device_profile_unique'),
        ),
    ]
