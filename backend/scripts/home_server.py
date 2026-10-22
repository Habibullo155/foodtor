"""
Боевой сервер магазина на своём компьютере: PostgreSQL → API → (Caddy) → SSH-туннель localhost.run.

    ./scripts/server.sh

Туннель выдаёт публичный https-адрес (*.lhr.life), он меняется при каждом подключении.
Скрипт публикует его на GitHub Pages (ветка gh-pages) — по постоянной ссылке
https://<аккаунт>.github.io/<репозиторий>/ покупатели всегда попадают на текущий адрес магазина.
Если туннель оборвался, скрипт поднимает новый и публикует новый адрес.
При остановке (Ctrl+C) на Pages появляется «магазин временно недоступен».

Данные (база, фото, ключи) — в backend/.server-data, в git не попадают.
Настройки (SMS.ru, почта, телефон магазина) — в backend/.server-data/server.env, пример — backend/server.env.example.
"""

import html
import json
import os
import re
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime
from pathlib import Path
from urllib.error import URLError
from urllib.request import ProxyHandler, build_opener

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
DATA = ROOT / ".server-data"
ADMIN_BUILD = REPO / "frontend" / "build" / "admin_web"
CADDYFILE = REPO / "deploy" / "Caddyfile.home"
API_PORT = int(os.getenv("API_PORT", "8000"))
CADDY_PORT = int(os.getenv("CADDY_PORT", "8080"))
TUNNEL_HOST = os.getenv("TUNNEL_HOST", "localhost.run")
TUNNEL_URL = re.compile(r"https://[a-z0-9]+\.lhr\.life")


def tool(name: str, required: bool = True) -> str | None:
    path = shutil.which(name)
    if not path and required:
        sys.exit(f"Не найден {name}: brew install {name}")
    return path


def log(msg: str) -> None:
    print(f"▶ {msg}", flush=True)


def read_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            out[key.strip()] = value.strip().strip('"').strip("'")
    return out


def start_database() -> str:
    import pgserver  # pip-пакет: PostgreSQL без Docker

    srv = pgserver.get_server(str(DATA / "pg"), cleanup_mode=None)
    sock = srv.get_uri().split("host=")[1]
    return f"postgresql+asyncpg://postgres@/postgres?host={sock}"


def system_proxy() -> str | None:
    """HTTP-прокси из настроек macOS (VPN-клиенты ставят его сами): без него туннель в некоторых сетях не пробивается."""
    if explicit := os.getenv("TUNNEL_PROXY"):
        return explicit
    scutil = shutil.which("scutil")
    if not scutil:
        return None
    out = subprocess.run([scutil, "--proxy"], capture_output=True, text=True).stdout  # noqa: S603
    vals = dict(re.findall(r"(\w+) : (\S+)", out))
    if vals.get("HTTPSEnable") == "1" and vals.get("HTTPSProxy"):
        return f"{vals['HTTPSProxy']}:{vals.get('HTTPSPort', '8080')}"
    return None


class Tunnel:
    def __init__(self, port: int) -> None:
        self.port = port
        self.proc: subprocess.Popen | None = None

    def start(self) -> str:
        cmd = [
            tool("ssh"),
            "-tt",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=20",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=20",
        ]  # fmt: skip
        if proxy := system_proxy():
            cmd += ["-o", f"ProxyCommand={tool('nc')} -X connect -x {proxy} %h %p"]
        cmd += ["-R", f"80:127.0.0.1:{self.port}", f"nokey@{TUNNEL_HOST}"]
        for attempt in range(1, 6):
            self.proc = subprocess.Popen(  # noqa: S603 — фиксированная команда ssh
                cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
            )
            found: list[str] = []

            def pump(proc: subprocess.Popen = self.proc, found: list[str] = found) -> None:
                for line in proc.stdout:  # type: ignore[union-attr]
                    if not found and (m := TUNNEL_URL.search(line)):
                        found.append(m.group(0))

            threading.Thread(target=pump, daemon=True).start()
            deadline = time.monotonic() + 40
            while not found and self.proc.poll() is None and time.monotonic() < deadline:
                time.sleep(0.3)
            if found:
                return found[0]
            self.stop()
            log(f"Туннель не поднялся (попытка {attempt}), пробуем ещё раз…")
            time.sleep(3)
        sys.exit("Не удалось открыть туннель — проверьте интернет/VPN и запустите снова")

    def alive(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()


def wait_healthy(url: str, seconds: int = 60) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            # мимо системного прокси macOS: он перехватил бы и запросы к 127.0.0.1
            with build_opener(ProxyHandler({})).open(url, timeout=3) as r:
                if r.status == 200:
                    return
        except (URLError, OSError):
            pass
        time.sleep(0.5)
    raise RuntimeError(f"Сервер не ответил на {url}")


def git(*args: str, cwd: Path = REPO, check: bool = True) -> str:
    return subprocess.run(  # noqa: S603 — фиксированные команды git
        [tool("git"), *args], cwd=cwd, check=check, capture_output=True, text=True
    ).stdout.strip()


def pages_html(shop_url: str | None, shop_name: str) -> str:
    name = html.escape(shop_name)
    stamp = datetime.now().strftime("%d.%m.%Y %H:%M")
    if shop_url:
        url = html.escape(shop_url)
        head = f'<meta http-equiv="refresh" content="0; url={url}/">'
        body = (
            f'<h1>{name}</h1><p>Открываем магазин…</p><p><a href="{url}/">Перейти в магазин</a> · '
            f'<a href="{url}/admin/">Админка</a></p><p class="m">Адрес обновлён {stamp}</p>'
        )
    else:
        head = ""
        body = f'<h1>{name}</h1><p>Магазин временно недоступен — скоро вернёмся.</p><p class="m">{stamp}</p>'
    return f"""<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{name}</title>{head}<meta name="robots" content="noindex">
<style>body{{font:16px/1.5 system-ui,sans-serif;background:#F7F3EA;color:#17291F;display:grid;place-items:center;
min-height:100vh;margin:0;text-align:center}}h1{{color:#0B5D3B}}a{{color:#0B5D3B;font-weight:600}}.m{{color:#5E6B62;font-size:13px}}</style>
</head><body><main>{body}</main></body></html>
"""


def publish(shop_url: str | None, shop_name: str) -> None:
    """Одна страница-переадресация в ветке gh-pages (история не копится: каждый раз один коммит)."""
    remote = git("remote", "get-url", "origin", check=False)
    if not remote:
        log("git remote origin не настроен — адрес на GitHub Pages не опубликован")
        return
    name = git("config", "user.name", check=False) or "FOODTOR server"
    email = git("config", "user.email", check=False) or "server@localhost"
    with tempfile.TemporaryDirectory() as tmp:
        site = Path(tmp)
        (site / "index.html").write_text(pages_html(shop_url, shop_name))
        (site / ".nojekyll").write_text("")
        git("init", "-q", "-b", "gh-pages", cwd=site)
        git("add", ".", cwd=site)
        git("-c", f"user.name={name}", "-c", f"user.email={email}", "commit", "-q", "-m", "chore: update shop address", cwd=site)
        result = subprocess.run(  # noqa: S603
            [tool("git"), "push", "-q", "--force", remote, "gh-pages"], cwd=site, capture_output=True, text=True
        )
    if result.returncode:
        log(f"Не удалось обновить GitHub Pages: {result.stderr.strip()}")
    else:
        log("Адрес опубликован на GitHub Pages")


def ensure_owner(env: dict[str, str]) -> None:
    flag = DATA / "owner_created"
    if flag.exists():
        return
    if not sys.stdin.isatty():
        log("Владельца ещё нет — запустите ./scripts/server.sh в терминале, скрипт спросит email и пароль")
        return
    print("\nПервый запуск: создаём владельца магазина (вход в админку).")
    email = input("  Email владельца: ").strip()
    name = input("  Имя и фамилия: ").strip()
    subprocess.run(  # noqa: S603
        [sys.executable, "-m", "scripts.create_owner", "--email", email, "--name", name], cwd=ROOT, env=env, check=True
    )
    flag.write_text(email)


def interrupt(*_: object) -> None:
    raise KeyboardInterrupt


def stop_all(procs: list[subprocess.Popen]) -> None:
    for proc in reversed(procs):
        if proc.poll() is None:
            proc.terminate()
    for proc in procs:
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            proc.kill()


def start_api(env: dict[str, str], public_url: str) -> subprocess.Popen:
    # адрес туннеля нужен API для canonical/sitemap — поэтому при новом адресе API перезапускается
    return subprocess.Popen(  # noqa: S603
        [
            sys.executable, "-m", "uvicorn", "app.main:app",
            "--host", "127.0.0.1", "--port", str(API_PORT),
            "--proxy-headers", "--no-server-header",
        ],  # fmt: skip
        cwd=ROOT,
        env={**env, "PUBLIC_SHOP_URL": public_url, "PUBLIC_API_URL": public_url},
    )


def main() -> None:
    tool("ssh")
    caddy = tool("caddy", required=False)
    entry_port = CADDY_PORT if caddy else API_PORT
    DATA.mkdir(exist_ok=True)
    (DATA / "media").mkdir(exist_ok=True)
    secret_file = DATA / "jwt_secret"
    if not secret_file.exists():
        secret_file.write_text(secrets.token_urlsafe(48))
        secret_file.chmod(0o600)
    settings = read_env_file(DATA / "server.env")
    shop_name = settings.get("SHOP_NAME", "FOODTOR")

    log("База данных")
    env = {
        **os.environ,
        **settings,
        "APP_ENV": "prod",
        "DATABASE_URL": start_database(),
        "JWT_SECRET": secret_file.read_text().strip(),
        "MEDIA_ROOT": str(DATA / "media"),
        "EXTRA_HOSTS": json.dumps(["*.lhr.life"]),
    }
    if ADMIN_BUILD.exists():
        env["ADMIN_STATIC_DIR"] = str(ADMIN_BUILD)
    env.pop("REDIS_URL", None)
    if not caddy:
        env["SERVE_MEDIA"] = "true"

    log("Миграции")
    local = {**env, "PUBLIC_SHOP_URL": "https://localhost", "PUBLIC_API_URL": "https://localhost"}
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=ROOT, env=local, check=True)  # noqa: S603
    ensure_owner(local)

    log("Туннель")
    tunnel = Tunnel(entry_port)
    public_url = tunnel.start()

    log("API и Caddy" if caddy else "API (Caddy не установлен — туннель идёт прямо в API)")
    services = [start_api(env, public_url)]
    if caddy:
        services.append(
            subprocess.Popen(  # noqa: S603
                [caddy, "run", "--config", str(CADDYFILE), "--adapter", "caddyfile"],
                env={**env, "CADDY_PORT": str(CADDY_PORT), "API_PORT": str(API_PORT)},
            )
        )
    signal.signal(signal.SIGTERM, interrupt)
    signal.signal(signal.SIGINT, interrupt)
    published = False
    try:
        wait_healthy(f"http://127.0.0.1:{entry_port}/health")
        publish(public_url, shop_name)
        published = True
        print(f"\n✅ Магазин: {public_url}\n   Админка: {public_url}/admin/")
        if not settings.get("SMSRU_API_ID"):
            print("   ⚠ Нет SMSRU_API_ID в backend/.server-data/server.env — покупатели не смогут войти по SMS")
        print("   Остановить — Ctrl+C\n")
        while all(p.poll() is None for p in services):
            if not tunnel.alive():
                log("Туннель оборвался — открываем новый")
                public_url = tunnel.start()
                stop_all([services[0]])
                services[0] = start_api(env, public_url)
                wait_healthy(f"http://127.0.0.1:{entry_port}/health")
                publish(public_url, shop_name)
                print(f"\n✅ Новый адрес магазина: {public_url}\n")
            time.sleep(2)
        log("Сервер остановился — выключаем всё")
    except KeyboardInterrupt:
        pass
    except RuntimeError as exc:
        log(str(exc))
    finally:
        tunnel.stop()
        stop_all(services)
        if published:
            publish(None, shop_name)


if __name__ == "__main__":
    main()
