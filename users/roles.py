from django.db import models


class CorporateRole(models.TextChoices):
    """Stable role identifiers shared by every corporate workspace."""

    OWNER = 'owner', 'Egasi'
    ADMIN = 'admin', 'Administrator'
    MANAGER = 'manager', 'Menejer'
    MEMBER = 'member', 'Xodim'


DEFAULT_CORPORATE_ROLE = CorporateRole.MEMBER

CORPORATE_ROLE_ORDER = (
    CorporateRole.OWNER,
    CorporateRole.ADMIN,
    CorporateRole.MANAGER,
    CorporateRole.MEMBER,
)

CORPORATE_ROLE_DESCRIPTIONS = {
    CorporateRole.OWNER: 'Tashkilot va barcha ish maydonlarini boshqaradi.',
    CorporateRole.ADMIN: 'Xodimlar, rollar va korporativ sozlamalarni boshqaradi.',
    CorporateRole.MANAGER: 'Jamoa ishini boshqaradi va korporativ muloqotda ajralib turadi.',
    CorporateRole.MEMBER: 'Korporativ chatning standart foydalanuvchisi.',
}


def role_catalog():
    return [
        {
            'value': role.value,
            'label': role.label,
            'description': CORPORATE_ROLE_DESCRIPTIONS[role],
        }
        for role in CORPORATE_ROLE_ORDER
    ]
