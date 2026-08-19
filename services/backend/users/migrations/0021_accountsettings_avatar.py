from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0020_userdevice_supported_protocols'),
    ]

    operations = [
        migrations.AddField(
            model_name='accountsettings',
            name='avatar_storage_key',
            field=models.CharField(blank=True, max_length=512),
        ),
    ]
