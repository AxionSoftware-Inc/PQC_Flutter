from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
        ('users', '0022_quarantine_invalid_ml_kem_devices'),
    ]

    operations = [
        migrations.CreateModel(
            name='AccountSettings',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('notifications_enabled', models.BooleanField(default=True)),
                ('notification_previews', models.BooleanField(default=True)),
                ('read_receipts_enabled', models.BooleanField(default=True)),
                ('typing_indicators_enabled', models.BooleanField(default=True)),
                ('last_seen_visibility', models.CharField(choices=[('everybody', 'Everybody'), ('contacts', 'Contacts'), ('nobody', 'Nobody')], default='contacts', max_length=16)),
                ('online_visibility', models.CharField(choices=[('everybody', 'Everybody'), ('contacts', 'Contacts'), ('nobody', 'Nobody')], default='contacts', max_length=16)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('user', models.OneToOneField(on_delete=django.db.models.deletion.CASCADE, related_name='account_settings', to=settings.AUTH_USER_MODEL)),
            ],
        ),
    ]
