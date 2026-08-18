"""Tamper-evident recovery audit ledger."""
import hashlib
import json

from django.db import transaction

from users.models import CryptoRecoveryAuditEvent


@transaction.atomic
def append_recovery_audit_event(*, user, event_type, device_id='', metadata=None):
    previous = CryptoRecoveryAuditEvent.objects.select_for_update().filter(
        user=user,
    ).order_by('-id').first()
    previous_hash = previous.event_hash if previous else ''
    canonical = json.dumps({
        'user_id': user.id,
        'event_type': event_type,
        'device_id': device_id,
        'metadata': metadata or {},
        'previous_hash': previous_hash,
    }, sort_keys=True, separators=(',', ':'))
    return CryptoRecoveryAuditEvent.objects.create(
        user=user,
        event_type=event_type,
        device_id=device_id,
        metadata=metadata or {},
        previous_hash=previous_hash,
        event_hash=hashlib.sha256(canonical.encode()).hexdigest(),
    )
