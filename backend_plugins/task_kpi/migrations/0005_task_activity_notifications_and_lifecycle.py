from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [('task_kpi', '0004_worktask_accepted_status')]

    operations = [
        migrations.AddField(
            model_name='worktask',
            name='cancelled_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name='worktask',
            name='cancellation_note',
            field=models.TextField(blank=True),
        ),
        migrations.CreateModel(
            name='TaskActivity',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('kind', models.CharField(choices=[('comment', 'Izoh'), ('workflow', 'Jarayon'), ('change', "O'zgarish"), ('system', 'Tizim')], default='comment', max_length=16)),
                ('body', models.TextField(blank=True)),
                ('metadata', models.JSONField(blank=True, default=dict)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('created_by', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='task_activities', to=settings.AUTH_USER_MODEL)),
                ('task', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='activities', to='task_kpi.worktask')),
            ],
            options={'ordering': ['created_at', 'id']},
        ),
        migrations.CreateModel(
            name='TaskWatcher',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('added_by', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('member', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='watched_tasks', to='users.workspacemember')),
                ('task', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='watchers', to='task_kpi.worktask')),
            ],
        ),
        migrations.CreateModel(
            name='TaskNotification',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('kind', models.CharField(max_length=24)),
                ('read_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('activity', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='notifications', to='task_kpi.taskactivity')),
                ('recipient', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='task_notifications', to='users.workspacemember')),
                ('task', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='notifications', to='task_kpi.worktask')),
            ],
            options={'ordering': ['-created_at', '-id']},
        ),
        migrations.AddField(
            model_name='taskattachment',
            name='activity',
            field=models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.CASCADE, related_name='attachments', to='task_kpi.taskactivity'),
        ),
        migrations.AddIndex(
            model_name='taskactivity',
            index=models.Index(fields=['task', 'created_at'], name='task_kpi_ta_task_id_2fef3e_idx'),
        ),
        migrations.AddIndex(
            model_name='tasknotification',
            index=models.Index(fields=['recipient', 'read_at', 'created_at'], name='task_kpi_ta_recipie_350072_idx'),
        ),
        migrations.AddConstraint(
            model_name='taskwatcher',
            constraint=models.UniqueConstraint(fields=('task', 'member'), name='task_kpi_unique_task_watcher'),
        ),
    ]
