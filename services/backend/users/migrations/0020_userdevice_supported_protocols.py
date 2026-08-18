from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0019_quarantine_invalid_ml_kem_devices'),
    ]

    operations = [
        migrations.AddField(
            model_name='userdevice',
            name='supported_protocols',
            field=models.JSONField(blank=True, default=list),
        ),
    ]
