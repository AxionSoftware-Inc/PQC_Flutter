from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0004_userdevice_pqc_public_key_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='userdevice',
            name='pqc_signing_algorithm',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name='userdevice',
            name='pqc_signing_public_key',
            field=models.TextField(blank=True),
        ),
    ]
