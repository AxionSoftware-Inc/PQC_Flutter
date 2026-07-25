from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.db.models import Q

from users.models import OrganizationMember, WorkspaceMember
from users.roles import CorporateRole


class Command(BaseCommand):
    help = (
        'Grant Owner to an existing account in every workspace where it is '
        'already an active member. This never adds the account to another company.'
    )

    def add_arguments(self, parser):
        parser.add_argument('--email', required=True)
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Print affected memberships without changing the database.',
        )

    @transaction.atomic
    def handle(self, *args, **options):
        email = options['email'].strip().lower()
        if not email:
            raise CommandError('A non-empty email is required.')

        User = get_user_model()
        users = list(
            User.objects.filter(
                Q(email__iexact=email) | Q(google_account__email__iexact=email)
            ).distinct()[:2]
        )
        if not users:
            raise CommandError(f'No account was found for {email}.')
        if len(users) != 1:
            raise CommandError(
                f'Multiple accounts matched {email}; resolve the duplicate first.'
            )

        user = users[0]
        memberships = list(
            WorkspaceMember.objects.select_related(
                'workspace',
                'workspace__organization',
                'organization_member',
            ).filter(
                organization_member__user=user,
                organization_member__is_active=True,
                is_active=True,
            )
        )
        if not memberships:
            raise CommandError(
                f'{email} is not an active member of any workspace.'
            )

        workspace_names = ', '.join(
            f'{item.workspace.organization.name}/{item.workspace.name}'
            for item in memberships
        )
        if options['dry_run']:
            self.stdout.write(
                f'DRY RUN: would grant Owner to {email} in {workspace_names}'
            )
            return

        organization_member_ids = {
            item.organization_member_id for item in memberships
        }
        OrganizationMember.objects.filter(
            id__in=organization_member_ids
        ).update(role=CorporateRole.OWNER)
        WorkspaceMember.objects.filter(
            id__in=[item.id for item in memberships]
        ).update(role=CorporateRole.OWNER)
        self.stdout.write(
            self.style.SUCCESS(
                f'Granted Owner to {email} in {workspace_names}'
            )
        )
