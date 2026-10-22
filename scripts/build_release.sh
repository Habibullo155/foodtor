#!/usr/bin/env bash
# Релизная сборка админки (Flutter) в deploy/web/admin. Магазин собирать не нужно: его HTML-страницы
# отдаёт сам бэкенд (backend/app/web). Админка ходит в API на своём же домене (/api) — Caddy проксирует.
#   SHOP_NAME="Свежая лавка" SUPPORT_PHONE="+7 (999) 000-00-00" SUPPORT_EMAIL=help@shop.ru ./scripts/build_release.sh
set -euo pipefail
cd "$(dirname "$0")/../frontend"

DEFINES=(
  --dart-define=APP_MODE=release
  --dart-define=SHOP_NAME="${SHOP_NAME:-SaaS Shop}"
  --dart-define=SUPPORT_PHONE="${SUPPORT_PHONE:-+7 (000) 000-00-00}"
  --dart-define=SUPPORT_EMAIL="${SUPPORT_EMAIL:-support@example.com}"
)

echo "▶ Проверки бэкенда (сайт магазина + API)"
VENV="../backend/.venv"
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q -r ../backend/requirements.txt pgserver pytest pytest-asyncio ruff pip-audit
(cd ../backend && .venv/bin/ruff check app tests scripts alembic && .venv/bin/pip-audit -r requirements.txt && .venv/bin/pytest -q)

echo "▶ Проверки админки"
flutter analyze --no-pub
flutter test test/release
flutter test --dart-define=APP_MODE=demo test/demo

echo "▶ Сборка админки"
# --no-web-resources-cdn: движок CanvasKit отдаём со своего сервера (без зависимости от CDN Google и строже CSP)
flutter build web -t lib/main_admin.dart -o ../deploy/web/admin --release --no-web-resources-cdn --no-source-maps \
  --no-wasm-dry-run "${DEFINES[@]}"
echo "✅ Готово: deploy/web/admin (магазин — в backend/app/web, выкладывается вместе с бэкендом)"
