from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('users', '0013_recovery_record_ledger')]

    operations = [
        migrations.AddField(
            model_name='cryptorecoveryauditevent',
            name='previous_hash',
            field=models.CharField(blank=True, max_length=64),
        ),
        migrations.AddField(
            model_name='cryptorecoveryauditevent',
            name='event_hash',
            field=models.CharField(blank=True, max_length=64, null=True, unique=True),
        ),
    ]
