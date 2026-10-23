#!/usr/bin/env bash
# Подготовка чистого VPS (Ubuntu/Debian) под магазин. Запускается один раз владельцем сервера:
#   ssh root@SERVER 'bash -s' < scripts/server_setup.sh
# Ставит Docker, включает файрвол (22/80/443), fail2ban, автообновления безопасности
# и выключает вход по паролю в SSH — только если на сервере уже есть ключ (иначе можно потерять доступ).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if [[ $EUID -ne 0 ]]; then echo "Запустите от root"; exit 1; fi
. /etc/os-release
echo "▶ Система: $PRETTY_NAME"

echo "▶ Обновления и пакеты"
apt-get update -q
apt-get upgrade -yq
apt-get install -yq ca-certificates curl rsync ufw fail2ban unattended-upgrades

if ! command -v docker >/dev/null; then
  echo "▶ Docker (официальный репозиторий)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -yq docker-ce docker-ce-cli containerd.io docker-compose-plugin
fi
systemctl enable --now docker

echo "▶ Файрвол: открыты только SSH и веб"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "▶ fail2ban: блокировка подбора пароля к SSH"
cat > /etc/fail2ban/jail.local <<'EOF'
[sshd]
enabled = true
maxretry = 5
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

echo "▶ Автоматические обновления безопасности"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

if [[ -s /root/.ssh/authorized_keys ]]; then
  echo "▶ SSH: вход только по ключу"
  cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
MaxAuthTries 4
EOF
  sshd -t && (systemctl reload ssh 2>/dev/null || systemctl reload sshd)
else
  echo "⚠ Ключа SSH нет — вход по паролю оставлен. Сначала: ssh-copy-id root@этот-сервер, потом запустите скрипт ещё раз"
fi

mkdir -p /opt/saasshop
echo "✅ Сервер готов: $(docker --version)"
