from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('task_kpi', '0003_task_attachment')]

    operations = [
        migrations.AlterField(
            model_name='worktask',
            name='status',
            field=models.CharField(
                choices=[
                    ('todo', 'Bajarilishi kerak'),
                    ('accepted', 'Qabul qilindi'),
                    ('in_progress', 'Jarayonda'),
                    ('submitted', 'Topshirildi'),
                    ('done', 'Qabul qilindi'),
                    ('returned', 'Qayta ishlashda'),
                    ('cancelled', 'Bekor qilindi'),
                ],
                default='todo',
                max_length=20,
            ),
        ),
    ]
