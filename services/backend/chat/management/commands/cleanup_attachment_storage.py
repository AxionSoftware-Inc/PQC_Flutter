from datetime import timedelta

from django.core.files.storage import default_storage
from django.core.management.base import BaseCommand
from django.db.models import Q
from django.utils import timezone

from chat.models import AttachmentUploadSession


class Command(BaseCommand):
    help = (
        'Expire abandoned attachment sessions and remove their temporary '
        'chunk objects.'
    )

    def add_arguments(self, parser):
        parser.add_argument(
            '--completed-retention-hours',
            type=int,
            default=24,
            help=(
                'How long to retain completed-session chunk objects before '
                'deleting them (default: 24).'
            ),
        )
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Report candidates without changing database or storage.',
        )

    def handle(self, *args, **options):
        now = timezone.now()
        retention_hours = options['completed_retention_hours']
        if retention_hours < 0:
            raise ValueError('--completed-retention-hours cannot be negative.')
        completed_cutoff = now - timedelta(hours=retention_hours)
        abandoned = AttachmentUploadSession.objects.filter(
            status__in=[
                AttachmentUploadSession.Status.PENDING,
                AttachmentUploadSession.Status.UPLOADING,
            ],
            expires_at__lte=now,
        )
        completed = AttachmentUploadSession.objects.filter(
            status=AttachmentUploadSession.Status.COMPLETED,
            updated_at__lte=completed_cutoff,
        )
        cleanup_sessions = list(
            AttachmentUploadSession.objects.filter(
                Q(pk__in=abandoned.values('pk'))
                | Q(pk__in=completed.values('pk'))
            ).prefetch_related('chunk_receipts')
        )

        dry_run = options['dry_run']
        deleted_objects = 0
        expired_sessions = 0
        for session in cleanup_sessions:
            keys = [
                receipt.storage_key
                for receipt in session.chunk_receipts.all()
                if receipt.storage_key
            ]
            if session.status in {
                AttachmentUploadSession.Status.PENDING,
                AttachmentUploadSession.Status.UPLOADING,
            }:
                expired_sessions += 1
                if session.blob_storage_key:
                    keys.append(session.blob_storage_key)
                if not dry_run:
                    session.status = AttachmentUploadSession.Status.EXPIRED
                    session.save(update_fields=['status', 'updated_at'])
            if not dry_run:
                for key in dict.fromkeys(keys):
                    default_storage.delete(key)
            deleted_objects += len(dict.fromkeys(keys))

        self.stdout.write(
            self.style.SUCCESS(
                f'attachment cleanup: sessions={len(cleanup_sessions)} '
                f'expired={expired_sessions} objects={deleted_objects} '
                f'dry_run={dry_run}'
            )
        )
