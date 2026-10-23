#!/usr/bin/env bash
# Создаёт deploy/.env на сервере один раз:  ./scripts/init_server_env.sh root@SERVER [домен]
# Пароль БД и ключ подписи сессий генерируются прямо на сервере и никуда не передаются.
# Ключ SMS.ru и SMTP берутся из backend/.server-data/server.env этого компьютера (если есть).
set -euo pipefail
HOST="${1:?usage: init_server_env.sh user@host [domain]}"
DOMAIN="${2:-foodtor.ru}"
DIR=/opt/saasshop
cd "$(dirname "$0")/.."

LOCAL=backend/.server-data/server.env
val() { if [[ -f $LOCAL ]]; then grep -E "^$1=" "$LOCAL" | tail -1 | cut -d= -f2- || true; fi; }

if ! ssh "$HOST" "mkdir -p $DIR/deploy && test ! -f $DIR/deploy/.env"; then
  echo "deploy/.env на сервере уже есть — не трогаю"
  exit 0
fi

# Секреты уходят через stdin, а не в командной строке (её видно в списке процессов)
remote_script() {
  printf 'SMSRU=%q\nSMTP_HOST_V=%q\nSMTP_PASS_V=%q\nDOMAIN=%q\nDIR=%q\n' \
    "$(val SMSRU_API_ID)" "$(val SMTP_HOST)" "$(val SMTP_PASSWORD)" "$DOMAIN" "$DIR"
  cat <<'REMOTE'
set -euo pipefail
gen() { head -c 96 /dev/urandom | base64 | tr -d '/+=\n' | head -c "$1"; }
umask 077
cat > "$DIR/deploy/.env" <<EOF
SHOP_DOMAIN=$DOMAIN
ADMIN_DOMAIN=admin.$DOMAIN
POSTGRES_PASSWORD=$(gen 40)
JWT_SECRET=$(gen 64)
TIMEZONE=Europe/Moscow
SHOP_NAME=FOODTOR
GEOCODER_CONTACT_EMAIL=no-reply@$DOMAIN
SMS_PROVIDER=smsru
SMSRU_API_ID=$SMSRU
SMTP_HOST=$SMTP_HOST_V
SMTP_PORT=465
SMTP_SECURITY=ssl
SMTP_USER=no-reply@$DOMAIN
SMTP_PASSWORD=$SMTP_PASS_V
SMTP_FROM=FOODTOR <no-reply@$DOMAIN>
EOF
echo "✅ $DIR/deploy/.env создан (права 600)"
REMOTE
}

remote_script | ssh "$HOST" "bash -s"
