from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0016_alter_historicaldevicekey_options'),
    ]

    operations = [
        migrations.AddField(
            model_name='googleaccount',
            name='avatar_url',
            field=models.URLField(blank=True),
        ),
    ]
