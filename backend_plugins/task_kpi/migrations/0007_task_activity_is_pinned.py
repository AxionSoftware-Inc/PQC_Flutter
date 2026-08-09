from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('task_kpi', '0006_kpi_history_and_task_started_at')]

    operations = [
        migrations.AddField(
            model_name='taskactivity',
            name='is_pinned',
            field=models.BooleanField(default=False),
        ),
    ]
