"""Системные роли и права. Идемпотентно — вызывается на старте API и в скриптах."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Role, SystemRole
from app.models.user import DEFAULT_ROLE_PERMISSIONS, role_permissions

ROLE_TITLES = {
    SystemRole.OWNER: "Владелец",
    SystemRole.MANAGER: "Менеджер",
    SystemRole.PICKER: "Сборщик заказов",
    SystemRole.COURIER: "Курьер",
    SystemRole.CUSTOMER: "Покупатель",
}


async def ensure_system_roles(session: AsyncSession) -> dict[SystemRole, Role]:
    roles: dict[SystemRole, Role] = {}
    for code, perms in DEFAULT_ROLE_PERMISSIONS.items():
        role = await session.scalar(select(Role).where(Role.code == code.value))
        if role is None:
            role = Role(
                code=code.value, title=ROLE_TITLES[code], is_staff=code is not SystemRole.CUSTOMER, is_system=True
            )
            session.add(role)
            await session.flush()
        existing = set(
            await session.scalars(select(role_permissions.c.permission).where(role_permissions.c.role_id == role.id))
        )
        missing = perms - existing
        if missing:
            await session.execute(role_permissions.insert(), [{"role_id": role.id, "permission": p} for p in missing])
        roles[code] = role
    return roles
