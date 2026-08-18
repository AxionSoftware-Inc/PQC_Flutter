import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    initial = True
    dependencies = [
        ('users', '0006_organization_organizationmember_workspace_invitation_and_more'),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]
    operations = [
        migrations.CreateModel(
            name='WorkTask',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=240)),
                ('description', models.TextField(blank=True)),
                ('status', models.CharField(choices=[('todo', 'Bajarilishi kerak'), ('in_progress', 'Jarayonda'), ('review', 'Tekshiruvda'), ('done', 'Bajarildi'), ('cancelled', 'Bekor qilindi')], default='todo', max_length=20)),
                ('priority', models.CharField(choices=[('low', 'Past'), ('normal', 'Oddiy'), ('high', 'Yuqori'), ('urgent', 'Shoshilinch')], default='normal', max_length=12)),
                ('due_at', models.DateTimeField(blank=True, null=True)),
                ('completed_at', models.DateTimeField(blank=True, null=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('assignee', models.ForeignKey(blank=True, null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='assigned_tasks', to='users.workspacemember')),
                ('created_by', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='created_work_tasks', to=settings.AUTH_USER_MODEL)),
                ('workspace', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='work_tasks', to='users.workspace')),
            ],
            options={'ordering': ['status', '-updated_at', '-id']},
        ),
        migrations.CreateModel(
            name='KpiGoal',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('title', models.CharField(max_length=180)),
                ('unit', models.CharField(default='ta', max_length=24)),
                ('target_value', models.DecimalField(decimal_places=2, max_digits=14)),
                ('current_value', models.DecimalField(decimal_places=2, default=0, max_digits=14)),
                ('period_start', models.DateField()),
                ('period_end', models.DateField()),
                ('is_active', models.BooleanField(default=True)),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('updated_at', models.DateTimeField(auto_now=True)),
                ('owner', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='kpi_goals', to='users.workspacemember')),
                ('workspace', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='kpi_goals', to='users.workspace')),
            ],
            options={'ordering': ['period_end', 'id']},
        ),
        migrations.AddIndex(model_name='worktask', index=models.Index(fields=['workspace', 'status'], name='task_kpi_wo_workspa_56e58b_idx')),
        migrations.AddIndex(model_name='worktask', index=models.Index(fields=['workspace', 'assignee'], name='task_kpi_wo_workspa_1cb0d4_idx')),
        migrations.AddIndex(model_name='kpigoal', index=models.Index(fields=['workspace', 'owner', 'is_active'], name='task_kpi_kp_workspa_06b52b_idx')),
    ]
