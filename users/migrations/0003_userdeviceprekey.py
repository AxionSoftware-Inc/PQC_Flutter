from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ('users', '0002_userdevice_identity_public_key_and_more'),
    ]

    operations = [
        migrations.CreateModel(
            name='UserDevicePreKey',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('key_id', models.CharField(max_length=64)),
                ('public_key', models.TextField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('used_at', models.DateTimeField(blank=True, null=True)),
                ('device', models.ForeignKey(on_delete=models.deletion.CASCADE, related_name='prekeys', to='users.userdevice')),
            ],
            options={
                'ordering': ['id'],
                'unique_together': {('device', 'key_id')},
            },
        ),
    ]
