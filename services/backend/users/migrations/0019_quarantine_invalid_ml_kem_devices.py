import base64

from django.db import migrations


ML_KEM_768_PUBLIC_KEY_BYTES = 1184
ML_KEM_POLYVEC_BYTES = 1152
ML_KEM_Q = 3329


def _is_valid_ml_kem_public_key(value):
    try:
        decoded = base64.b64decode(value, validate=True)
    except Exception:
        return False
    if len(decoded) != ML_KEM_768_PUBLIC_KEY_BYTES:
        return False
    encoded_polyvec = decoded[:ML_KEM_POLYVEC_BYTES]
    for offset in range(0, len(encoded_polyvec), 3):
        first = encoded_polyvec[offset] | ((encoded_polyvec[offset + 1] & 0x0F) << 8)
        second = (encoded_polyvec[offset + 1] >> 4) | (encoded_polyvec[offset + 2] << 4)
        if first >= ML_KEM_Q or second >= ML_KEM_Q:
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
    dependencies = [
        ('users', '0018_recovery_access_grant'),
    ]

    operations = [
        migrations.RunPython(quarantine_invalid_devices, migrations.RunPython.noop),
    ]
