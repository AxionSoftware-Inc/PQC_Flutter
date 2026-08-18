from django.db import migrations


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0015_recovery_approval_and_record_revocation'),
    ]

    operations = [
        migrations.AlterModelOptions(
            name='historicaldevicekey',
            options={'ordering': ['id']},
        ),
    ]
