from dataclasses import dataclass

from users.roles import CorporateRole


class AccessPermission:
    WORKSPACE_VIEW = 'workspace.view'
    WORKSPACE_MANAGE = 'workspace.manage'
    MEMBERS_VIEW = 'members.view'
    MEMBERS_INVITE = 'members.invite'
    MEMBERS_MANAGE = 'members.manage'
    ROLES_VIEW = 'roles.view'
    ROLES_MANAGE = 'roles.manage'
    DEVICES_VIEW = 'devices.view'
    DEVICES_REVOKE = 'devices.revoke'
    GROUPS_CREATE = 'groups.create'
    GROUPS_MANAGE = 'groups.manage'
    SECURITY_VIEW = 'security.view'
    SECURITY_MANAGE = 'security.manage'
    AUDIT_VIEW = 'audit.view'
    MESSAGES_SEND = 'messages.send'
    FILES_SEND = 'files.send'


@dataclass(frozen=True)
class PermissionDefinition:
    code: str
    label: str
    description: str
    category: str

    def to_dict(self) -> dict[str, str]:
        return {
            'code': self.code,
            'label': self.label,
            'description': self.description,
            'category': self.category,
        }


PERMISSION_CATALOG = (
    PermissionDefinition(AccessPermission.WORKSPACE_VIEW, 'Ish maydonini ko‘rish', 'Ish maydoni va uning asosiy ma’lumotlarini ko‘radi.', 'workspace'),
    PermissionDefinition(AccessPermission.WORKSPACE_MANAGE, 'Ish maydonini boshqarish', 'Ish maydoni siyosati va sozlamalarini o‘zgartiradi.', 'workspace'),
    PermissionDefinition(AccessPermission.MEMBERS_VIEW, 'Xodimlarni ko‘rish', 'Ish maydonidagi xodimlar ro‘yxatini ko‘radi.', 'members'),
    PermissionDefinition(AccessPermission.MEMBERS_INVITE, 'Xodim taklif qilish', 'Yangi xodimlarga taklif yuboradi.', 'members'),
    PermissionDefinition(AccessPermission.MEMBERS_MANAGE, 'Xodimlarni boshqarish', 'Xodimni faolsizlantiradi va standart rolini o‘zgartiradi.', 'members'),
    PermissionDefinition(AccessPermission.ROLES_VIEW, 'Rollarni ko‘rish', 'Standart va maxsus rollarni ko‘radi.', 'roles'),
    PermissionDefinition(AccessPermission.ROLES_MANAGE, 'Rollarni boshqarish', 'Maxsus rol, permission va biriktirishlarni boshqaradi.', 'roles'),
    PermissionDefinition(AccessPermission.DEVICES_VIEW, 'Qurilmalarni ko‘rish', 'Ro‘yxatdan o‘tgan qurilmalar holatini ko‘radi.', 'security'),
    PermissionDefinition(AccessPermission.DEVICES_REVOKE, 'Qurilmani bekor qilish', 'Kompaniya siyosati doirasida qurilma seansini bekor qiladi.', 'security'),
    PermissionDefinition(AccessPermission.GROUPS_CREATE, 'Guruh yaratish', 'Yangi guruh suhbatlarini yaratadi.', 'messaging'),
    PermissionDefinition(AccessPermission.GROUPS_MANAGE, 'Guruhlarni boshqarish', 'Guruh a’zolari va sozlamalarini boshqaradi.', 'messaging'),
    PermissionDefinition(AccessPermission.SECURITY_VIEW, 'Xavfsizlik holatini ko‘rish', 'Kalit va recovery holati metrikalarini ko‘radi.', 'security'),
    PermissionDefinition(AccessPermission.SECURITY_MANAGE, 'Xavfsizlik siyosatini boshqarish', 'Xavfsizlik va recovery siyosatini o‘zgartiradi.', 'security'),
    PermissionDefinition(AccessPermission.AUDIT_VIEW, 'Auditni ko‘rish', 'Maxfiy matnsiz boshqaruv auditini ko‘radi.', 'audit'),
    PermissionDefinition(AccessPermission.MESSAGES_SEND, 'Xabar yuborish', 'Ish maydoni suhbatlarida xabar yuboradi.', 'messaging'),
    PermissionDefinition(AccessPermission.FILES_SEND, 'Fayl yuborish', 'Ish maydoni suhbatlarida fayl yuboradi.', 'messaging'),
)

PERMISSIONS_BY_CODE = {item.code: item for item in PERMISSION_CATALOG}

MEMBER_PERMISSIONS = frozenset(
    {
        AccessPermission.WORKSPACE_VIEW,
        AccessPermission.MEMBERS_VIEW,
        AccessPermission.ROLES_VIEW,
        AccessPermission.GROUPS_CREATE,
        AccessPermission.MESSAGES_SEND,
        AccessPermission.FILES_SEND,
    }
)

MANAGER_PERMISSIONS = MEMBER_PERMISSIONS | {
    AccessPermission.MEMBERS_INVITE,
    AccessPermission.GROUPS_MANAGE,
    AccessPermission.DEVICES_VIEW,
    AccessPermission.SECURITY_VIEW,
}

ADMIN_PERMISSIONS = frozenset(PERMISSIONS_BY_CODE) - {
    AccessPermission.WORKSPACE_MANAGE,
}

BUILT_IN_ROLE_PERMISSIONS = {
    CorporateRole.OWNER: frozenset(PERMISSIONS_BY_CODE),
    CorporateRole.ADMIN: ADMIN_PERMISSIONS,
    CorporateRole.MANAGER: MANAGER_PERMISSIONS,
    CorporateRole.MEMBER: MEMBER_PERMISSIONS,
}


def permission_catalog() -> list[dict[str, str]]:
    return [item.to_dict() for item in PERMISSION_CATALOG]
