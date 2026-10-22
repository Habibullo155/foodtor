"""
Создание первого владельца в пустой (релизной) базе.

    docker compose exec api python -m scripts.create_owner --email owner@shop.ru --name "Имя Фамилия"

Пароль запрашивается скрыто (getpass) или берётся из OWNER_PASSWORD — в истории команд он не остаётся.
Повторный запуск с тем же email меняет пароль (сброс доступа владельца).
"""

import argparse
import asyncio
import getpass
import os
import sys

from sqlalchemy import func, select

from app.core.security import hash_password
from app.db.session import SessionFactory
from app.models import SystemRole, User
from app.services.bootstrap import ensure_system_roles


async def main(email: str, name: str, password: str) -> None:
    async with SessionFactory() as session, session.begin():
        roles = await ensure_system_roles(session)
        user = await session.scalar(select(User).where(func.lower(User.email) == email.lower()))
        if user is None:
            user = User(email=email.lower(), full_name=name, role_id=roles[SystemRole.OWNER].id)
            session.add(user)
            action = "создан"
        else:
            action = "обновлён"
        user.password_hash = hash_password(password)
        user.role_id = roles[SystemRole.OWNER].id
        user.is_active = True
    print(f"Владелец {email} {action}.")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--email", required=True)
    ap.add_argument("--name", required=True)
    args = ap.parse_args()
    pw = os.getenv("OWNER_PASSWORD") or getpass.getpass("Пароль владельца (мин. 12 символов): ")
    if len(pw) < 12 or pw.isdigit() or pw.isalpha():
        sys.exit("Пароль слишком простой: минимум 12 символов, буквы и цифры.")
    asyncio.run(main(args.email, args.name, pw))
