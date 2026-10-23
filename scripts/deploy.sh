#!/usr/bin/env bash
# Выкладка на VPS по SSH:  ./scripts/deploy.sh user@server.ru
# На сервере нужен только Docker (docker compose v2). Файл deploy/.env создаётся на сервере один раз вручную.
set -euo pipefail
HOST="${1:?usage: deploy.sh user@host}"
DIR=/opt/saasshop
cd "$(dirname "$0")/.."

[[ -d deploy/web/admin ]] || { echo "Сначала ./scripts/build_release.sh (сборка админки)"; exit 1; }

echo "▶ Копирую файлы на $HOST:$DIR"
rsync -az --delete --exclude '.env' --exclude 'backups/' deploy/ "$HOST:$DIR/deploy/"
rsync -az --delete --exclude '.env' --exclude '__pycache__' --exclude 'tests' --exclude '.demo-db' --exclude 'media' \
  --exclude '.venv' --exclude '.server-data' --exclude '.pytest_cache' --exclude '.ruff_cache' \
  backend/ "$HOST:$DIR/backend/"

echo "▶ Перезапуск (миграции БД применяются автоматически при старте API)"
ssh "$HOST" "cd $DIR && test -f deploy/.env || { echo 'Нет deploy/.env — создайте из deploy/.env.example'; exit 1; } \
  && docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env up -d --build \
  && docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env ps"
echo "✅ Выложено. Первый владелец: ssh $HOST 'cd $DIR && docker compose -f deploy/docker-compose.prod.yml exec api python -m scripts.create_owner --email you@shop.ru --name \"Имя Фамилия\"'"
