from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [('task_kpi', '0005_task_activity_notifications_and_lifecycle')]

    operations = [
        migrations.AddField(
            model_name='worktask',
            name='started_at',
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.CreateModel(
            name='KpiGoalHistory',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('target_value', models.DecimalField(decimal_places=2, max_digits=14)),
                ('current_value', models.DecimalField(decimal_places=2, max_digits=14)),
                ('period_start', models.DateField()),
                ('period_end', models.DateField()),
                ('created_at', models.DateTimeField(auto_now_add=True)),
                ('changed_by', models.ForeignKey(null=True, on_delete=django.db.models.deletion.SET_NULL, related_name='+', to=settings.AUTH_USER_MODEL)),
                ('goal', models.ForeignKey(on_delete=django.db.models.deletion.CASCADE, related_name='history', to='task_kpi.kpigoal')),
            ],
            options={'ordering': ['-created_at', '-id']},
        ),
    ]
