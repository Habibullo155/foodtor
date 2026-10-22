#!/usr/bin/env bash
# Сервер магазина на этом компьютере: база, API, Caddy (если установлен) и SSH-туннель с публичным https-адресом.
# Адрес публикуется на GitHub Pages: https://<аккаунт>.github.io/<репозиторий>/ ведёт в магазин.
#   ./scripts/server.sh            → собрать админку (если её нет) и запустить
#   ./scripts/server.sh --build    → пересобрать админку перед запуском
# Нужны: Python 3.11+, Flutter (для админки). Caddy — по желанию (brew install caddy).
# Настройки (SMS.ru, почта, телефон) — backend/.server-data/server.env, пример — backend/server.env.example.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

command -v caddy >/dev/null || echo "▶ Caddy не найден — работаем без него (brew install caddy, если нужен)"

VENV="$ROOT/backend/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "▶ Окружение Python (один раз)…"
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q -r "$ROOT/backend/requirements.txt" pgserver

if [[ "${1:-}" == "--build" || ! -f "$ROOT/frontend/build/admin_web/index.html" ]]; then
  echo "▶ Сборка админки (несколько минут)…"
  (cd "$ROOT/frontend" && flutter build web -t lib/main_admin.dart -o build/admin_web --base-href /admin/ \
    --no-web-resources-cdn --no-tree-shake-icons --no-wasm-dry-run)
fi

mkdir -p "$ROOT/backend/.server-data"
if [[ ! -f "$ROOT/backend/.server-data/server.env" ]]; then
  cp "$ROOT/backend/server.env.example" "$ROOT/backend/.server-data/server.env"
  echo "▶ Создан backend/.server-data/server.env — впишите туда ключ SMS.ru и контакты магазина"
fi

cd "$ROOT/backend"
exec "$VENV/bin/python" -m scripts.home_server
