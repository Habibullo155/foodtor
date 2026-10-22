#!/usr/bin/env bash
# Демо для показа: настоящий сайт магазина (HTML с сервера) + админка, на локальной базе с демо-данными.
#   ./scripts/demo.sh            → http://localhost:8765 — магазин, http://localhost:8765/admin/ — админка
#   ./scripts/demo.sh --no-build → без пересборки админки (быстрый старт)
# Нужны: Python 3.11+, Flutter (только для админки). Docker не нужен — PostgreSQL ставится pip-пакетом.
# Логины сотрудников — DEMO_ACCOUNTS.md; покупательница — вход по SMS +7 916 123-45-67 (код покажется на экране).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VENV="$ROOT/backend/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  echo "▶ Окружение Python (один раз)…"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$ROOT/backend/requirements.txt" pgserver
fi

if [[ "${1:-}" != "--no-build" ]]; then
  echo "▶ Сборка админки (несколько минут)…"
  (cd "$ROOT/frontend" && flutter build web -t lib/main_admin.dart -o build/admin_web --base-href /admin/ \
    --no-web-resources-cdn --no-tree-shake-icons --no-wasm-dry-run)
fi

cd "$ROOT/backend"
exec "$VENV/bin/python" -m scripts.demo_server
