from django.db import migrations


def repair_columns(apps, schema_editor):
    """Add only columns missing from a partially-applied 0007 migration."""
    connection = schema_editor.connection

    def columns(table_name):
        with connection.cursor() as cursor:
            return {
                column.name
                for column in connection.introspection.get_table_description(
                    cursor, table_name
                )
            }

    attachment = apps.get_model('chat', 'MessageAttachment')
    existing = columns('chat_messageattachment')
    for field_name in ('conversation_epoch_id', 'recovery_manifest_sequence'):
        if field_name not in existing:
            schema_editor.add_field(attachment, attachment._meta.get_field(field_name))

    session = apps.get_model('chat', 'AttachmentUploadSession')
    existing = columns('chat_attachmentuploadsession')
    for field_name in ('conversation_epoch_id', 'recovery_manifest_sequence'):
        if field_name not in existing:
            schema_editor.add_field(session, session._meta.get_field(field_name))


class Migration(migrations.Migration):
    """Repair databases where 0007 was recorded but its DDL was incomplete."""

    dependencies = [('chat', '0007_attachment_epoch_binding')]
    operations = [migrations.RunPython(repair_columns, migrations.RunPython.noop)]
