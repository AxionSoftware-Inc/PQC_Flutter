from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('users', '0006_organization_organizationmember_workspace_invitation_and_more'),
    ]

    operations = [
        migrations.AddField(
            model_name='userdevice',
            name='first_seen_at',
            field=models.DateTimeField(auto_now_add=True, default=None),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name='userdevice',
            name='last_seen_at',
            field=models.DateTimeField(auto_now_add=True, default=None),
            preserve_default=False,
        ),
        migrations.AddField(
            model_name='userdevice',
            name='profile_fingerprint',
            field=models.CharField(blank=True, max_length=128),
        ),
        migrations.AddField(
            model_name='userdevice',
            name='replaced_by',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='replaced_devices', to='users.userdevice'),
        ),
        migrations.AddField(
            model_name='userdevice',
            name='revoked_reason',
            field=models.CharField(blank=True, max_length=255),
        ),
        migrations.AddField(
            model_name='userdevice',
            name='status',
            field=models.CharField(choices=[('active', 'Active'), ('inactive', 'Inactive'), ('revoked', 'Revoked')], default='active', max_length=16),
        ),
    ]
