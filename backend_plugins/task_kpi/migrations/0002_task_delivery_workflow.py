from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [('task_kpi', '0001_initial')]
    operations = [
        migrations.AddField(model_name='worktask', name='completion_note', field=models.TextField(blank=True)),
        migrations.AddField(model_name='worktask', name='review_note', field=models.TextField(blank=True)),
        migrations.AddField(model_name='worktask', name='submitted_at', field=models.DateTimeField(blank=True, null=True)),
        migrations.AddField(model_name='worktask', name='reviewed_at', field=models.DateTimeField(blank=True, null=True)),
        migrations.AlterField(model_name='worktask', name='status', field=models.CharField(choices=[('todo', 'Bajarilishi kerak'), ('in_progress', 'Jarayonda'), ('submitted', 'Topshirildi'), ('done', 'Qabul qilindi'), ('returned', 'Qayta ishlashda'), ('cancelled', 'Bekor qilindi')], default='todo', max_length=20)),
    ]
