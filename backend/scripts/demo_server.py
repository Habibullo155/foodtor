"""
Локальное демо без Docker: PostgreSQL (pip-пакет pgserver) → миграции → демо-данные → сайт.

    python -m scripts.demo_server            # http://localhost:8765 — магазин, /admin — админка

Данные лежат в backend/.demo-db и переживают перезапуск. Пароли сотрудников — из ../DEMO_ACCOUNTS.md.
"""

import os
import re
import secrets
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / ".demo-db"
ACCOUNTS = ROOT.parent / "DEMO_ACCOUNTS.md"
ADMIN_BUILD = ROOT.parent / "frontend" / "build" / "admin_web"
PORT = int(os.getenv("PORT", "8765"))


def passwords() -> dict[str, str]:
    if not ACCOUNTS.exists():
        sys.exit("Нет DEMO_ACCOUNTS.md — в нём пароли демо-сотрудников")
    text = ACCOUNTS.read_text()
    out = {}
    for role in ("owner", "manager", "picker", "courier"):
        m = re.search(rf"`{role}@saasshop\.local` \| `([^`]+)`", text)
        if not m:
            sys.exit(f"В DEMO_ACCOUNTS.md нет пароля для {role}@saasshop.local")
        out[f"DEMO_{role.upper()}_PASSWORD"] = m.group(1)
    return out


def main() -> None:
    import pgserver  # pip install pgserver

    DATA.mkdir(exist_ok=True)
    secret_file = DATA / "jwt_secret"
    if not secret_file.exists():
        secret_file.write_text(secrets.token_urlsafe(48))
    srv = pgserver.get_server(str(DATA / "pg"), cleanup_mode=None)  # не останавливать при выходе скрипта
    sock = srv.get_uri().split("host=")[1]
    env = {
        **os.environ,
        **passwords(),
        "DATABASE_URL": f"postgresql+asyncpg://postgres@/postgres?host={sock}",
        "JWT_SECRET": secret_file.read_text(),
        "APP_ENV": "dev",
        "SMS_PROVIDER": "console",
        "PUBLIC_SHOP_URL": f"http://localhost:{PORT}",
        "PUBLIC_API_URL": f"http://localhost:{PORT}",
        "MEDIA_ROOT": str(DATA / "media"),
    }
    if ADMIN_BUILD.exists():
        env["ADMIN_STATIC_DIR"] = str(ADMIN_BUILD)
    run = lambda *cmd: subprocess.run(cmd, cwd=ROOT, env=env, check=True)  # noqa: E731, S603 — фиксированные команды
    run(sys.executable, "-m", "alembic", "upgrade", "head")
    run(sys.executable, "-m", "scripts.seed_demo")
    print(f"\n✅ Магазин: http://localhost:{PORT}")
    print(
        f"   Админка: http://localhost:{PORT}/admin/"
        + ("" if ADMIN_BUILD.exists() else "  (не собрана: ./scripts/demo.sh соберёт)")
    )
    print("   Покупательница: вход по SMS +7 916 123-45-67 — код покажется на экране\n")
    uvicorn = [
        sys.executable,
        "-m",
        "uvicorn",
        "app.main:app",
        "--host",
        "127.0.0.1",
        "--port",
        str(PORT),
        "--proxy-headers",
        "--no-server-header",
    ]
    if os.getenv("RELOAD"):  # разработка: перезапуск при изменении кода
        uvicorn += ["--reload", "--reload-dir", str(ROOT / "app")]
    os.execvpe(sys.executable, uvicorn, env)  # noqa: S606 — тот же интерпретатор, фиксированные аргументы


if __name__ == "__main__":
    main()
