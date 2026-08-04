import base64

from django.db import migrations


def _is_valid_ml_kem_public_key(value):
    try:
        decoded = base64.b64decode(value, validate=True)
    except Exception:
        return False
    if len(decoded) != 1184:
        return False
    for offset in range(0, 1152, 3):
        first = decoded[offset] | ((decoded[offset + 1] & 0x0F) << 8)
        second = (decoded[offset + 1] >> 4) | (decoded[offset + 2] << 4)
        if first >= 3329 or second >= 3329:
            return False
    return True


def quarantine_invalid_devices(apps, schema_editor):
    UserDevice = apps.get_model('users', 'UserDevice')
    active_devices = UserDevice.objects.filter(
        status='active',
        pqc_algorithm='ml-kem-768',
    ).exclude(pqc_public_key='')
    invalid_ids = [
        device.id
        for device in active_devices.iterator()
        if not _is_valid_ml_kem_public_key(device.pqc_public_key)
    ]
    if invalid_ids:
        UserDevice.objects.filter(id__in=invalid_ids).update(
            status='inactive',
            revoked_reason='invalid ml-kem-768 public key quarantined',
        )


class Migration(migrations.Migration):
    dependencies = [('users', '0021_recovery_access_grant')]

    operations = [
        migrations.RunPython(quarantine_invalid_devices, migrations.RunPython.noop),
    ]
