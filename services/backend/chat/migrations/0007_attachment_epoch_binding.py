from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('chat', '0006_conversationcryptoepoch')]

    operations = [
        migrations.AddField(
            model_name='messageattachment',
            name='conversation_epoch_id',
            field=models.CharField(blank=True, max_length=128),
        ),
        migrations.AddField(
            model_name='messageattachment',
            name='recovery_manifest_sequence',
            field=models.PositiveBigIntegerField(default=0),
        ),
        migrations.AddField(
            model_name='attachmentuploadsession',
            name='conversation_epoch_id',
            field=models.CharField(blank=True, max_length=128),
        ),
        migrations.AddField(
            model_name='attachmentuploadsession',
            name='recovery_manifest_sequence',
            field=models.PositiveBigIntegerField(default=0),
        ),
    ]
