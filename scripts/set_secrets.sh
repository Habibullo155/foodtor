#!/usr/bin/env bash
# Переносит ключи SMS.ru и почты из deploy/secrets.env на сервер, перезапускает магазин и проверяет их.
#   cp deploy/secrets.env.example deploy/secrets.env   # один раз, затем впишите значения
#   ./scripts/set_secrets.sh [root@45.129.128.9]
set -euo pipefail
HOST="${1:-root@45.129.128.9}"
DIR=/opt/saasshop
cd "$(dirname "$0")/.."

FILE=deploy/secrets.env
if [[ ! -f $FILE ]]; then
  cp deploy/secrets.env.example "$FILE"
  echo "Создан $FILE — впишите в него значения и запустите скрипт ещё раз"
  exit 1
fi

KEYS=(SMSRU_API_ID SMS_SENDER SMTP_HOST SMTP_PORT SMTP_SECURITY SMTP_USER SMTP_PASSWORD SMTP_FROM GEOCODER_CONTACT_EMAIL PEXELS_API_KEY)
pairs=""
for key in "${KEYS[@]}"; do
  value=$(grep -E "^$key=" "$FILE" | tail -1 | cut -d= -f2- || true)
  value="${value%\"}"; value="${value#\"}"
  [[ -z $value ]] && continue
  if [[ $value == *$'\n'* || $value == *"'"* ]]; then
    echo "В $key есть недопустимый символ (кавычка или перенос строки)"; exit 1
  fi
  pairs+="$key=$value"$'\n'
done
if [[ -z $pairs ]]; then
  echo "В $FILE нет ни одного значения"; exit 1
fi

# значения идут через stdin — в списке процессов сервера их не видно
{
  printf 'DIR=%q\n' "$DIR"
  printf 'PAIRS=%q\n' "$pairs"
  cat <<'REMOTE'
set -euo pipefail
ENV="$DIR/deploy/.env"
test -f "$ENV" || { echo "Нет $ENV — сначала scripts/init_server_env.sh"; exit 1; }
cp -p "$ENV" "$ENV.bak"
while IFS= read -r line; do
  [[ -z $line ]] && continue
  key="${line%%=*}"
  grep -v "^$key=" "$ENV" > "$ENV.tmp" || true
  printf '%s\n' "$line" >> "$ENV.tmp"
  mv "$ENV.tmp" "$ENV"
  echo "  ✓ $key"
done <<< "$PAIRS"
grep -q '^SMS_PROVIDER=' "$ENV" || echo 'SMS_PROVIDER=smsru' >> "$ENV"
chmod 600 "$ENV"

cd "$DIR"
compose="docker compose -f deploy/docker-compose.prod.yml --env-file deploy/.env"
echo "▶ Перезапуск магазина с новыми ключами"
$compose up -d api >/dev/null
for _ in $(seq 1 30); do
  $compose exec -T api python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" 2>/dev/null && break
  sleep 2
done

echo "▶ Проверка"
$compose exec -T api python - <<'PY'
import json, smtplib, ssl, urllib.request
from app.core.config import get_settings

s = get_settings()
if s.smsru_api_id and s.smsru_api_id.get_secret_value():
    try:
        url = "https://sms.ru/my/balance?json=1&api_id=" + s.smsru_api_id.get_secret_value()
        r = json.load(urllib.request.urlopen(url, timeout=15))
        if r.get("status") == "OK":
            print(f"  SMS.ru: ключ верный, баланс {r['balance']} ₽" + ("  ⚠ пополните баланс" if float(r["balance"]) < 50 else ""))
        else:
            print(f"  SMS.ru: ошибка — {r.get('status_text', r)}")
    except Exception as e:
        print(f"  SMS.ru: не удалось проверить — {e}")
else:
    print("  SMS.ru: ключ не задан")

if s.smtp_host and s.smtp_password:
    try:
        if s.smtp_security == "ssl":
            box = smtplib.SMTP_SSL(s.smtp_host, s.smtp_port, timeout=15, context=ssl.create_default_context())
        else:
            box = smtplib.SMTP(s.smtp_host, s.smtp_port, timeout=15)
            box.starttls(context=ssl.create_default_context())
        box.login(s.smtp_user, s.smtp_password.get_secret_value())
        box.quit()
        print(f"  Почта: вход на {s.smtp_host} как {s.smtp_user} — успешно")
    except Exception as e:
        print(f"  Почта: не удалось войти — {e}")
else:
    print("  Почта: SMTP не задан")
PY
if grep -q '^PEXELS_API_KEY=.' "$ENV"; then
  echo "▶ Фото товаров с Pexels (только там, где пока рисунок; несколько минут)"
  $compose exec -T api python -m scripts.fetch_photos | tail -5
fi
echo "✅ Готово. Прежняя версия настроек: $ENV.bak"
REMOTE
} | ssh "$HOST" "bash -s"
