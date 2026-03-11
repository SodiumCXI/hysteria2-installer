#!/bin/bash

set -euo pipefail

[ "$EUID" -ne 0 ] && { echo "Error: run as root"; exit 1; }

MANAGER_PATH="/usr/local/bin/h2"
STATE_FILE="/etc/hysteria/.state"
USERS_FILE="/etc/hysteria/.users"
CONFIG_FILE="/etc/hysteria/config.yaml"

rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; true; }
die()  { echo "Error: $*"; exit 1; }

if [ -f "/usr/local/bin/h2" ]; then
  echo "Hysteria2 is already installed. Use 'h2 help'."
  exit 0
fi

SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)
[ -z "$SERVER_IP" ] && die "Could not detect external IP"

echo ""
echo "Hysteria2 Setup"
echo ""

read -rp "Port [443]: " _in; PORT="${_in:-443}"
read -rp "Obfs password [random]: " _in; OBFS_PASS="${_in:-$(rand 16)}"
read -rp "SNI [google.com]: " _in; MASQ_URL="https://${_in:-google.com}/"
read -rp "Key name [Hysteria2]: " _in; KEY_NAME="${_in:-Hysteria2}"

echo ""
echo "Auth mode:"
echo "  1  Single password"
echo "  2  Users"
echo ""
read -rp "Choose [1/2]: " _in; AUTH_MODE="${_in:-1}"

if [ "$AUTH_MODE" = "1" ]; then
  read -rp "Auth password [random]: " _in; AUTH_PASS="${_in:-$(rand 16)}"
else
  AUTH_PASS=""
  read -rp "First username: " _in; FIRST_USER="${_in:-user}"
  FIRST_PASS=$(rand 16)
fi
echo ""

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | grep -v "^$" | sed '/Congratulation/q'

echo "Generating certificate..."
mkdir -p /etc/hysteria
chown hysteria:hysteria /etc/hysteria
chmod 750 /etc/hysteria

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /etc/hysteria/server.key \
  -out /etc/hysteria/server.crt \
  -days 36500 -subj "/CN=${SERVER_IP}" 2>/dev/null

chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
chmod 600 /etc/hysteria/server.key
chmod 644 /etc/hysteria/server.crt
echo "Done."

echo "Writing config..."

if [ "$AUTH_MODE" = "2" ]; then
  echo "${FIRST_USER}:${FIRST_PASS}" > "$USERS_FILE"
  chmod 600 "$USERS_FILE"

  cat > "$CONFIG_FILE" <<CONF
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

bandwidth:
  up: 1 gbps
  down: 1 gbps

auth:
  type: userpass
  userpass:
    ${FIRST_USER}: ${FIRST_PASS}

masquerade:
  type: proxy
  proxy:
    url: ${MASQ_URL}
    rewriteHost: true

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASS}
CONF
else
  cat > "$CONFIG_FILE" <<CONF
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

bandwidth:
  up: 1 gbps
  down: 1 gbps

auth:
  type: password
  password: ${AUTH_PASS}

masquerade:
  type: proxy
  proxy:
    url: ${MASQ_URL}
    rewriteHost: true

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASS}
CONF
fi

cat > "$STATE_FILE" <<STATE
SERVER_IP="${SERVER_IP}"
PORT="${PORT}"
AUTH_PASS="${AUTH_PASS}"
OBFS_PASS="${OBFS_PASS}"
MASQ_URL="${MASQ_URL}"
KEY_NAME="${KEY_NAME}"
AUTH_MODE="${AUTH_MODE}"
STATE
chmod 600 "$STATE_FILE"
echo "Done. Config: $CONFIG_FILE"

echo "Configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow "${PORT}/udp" >/dev/null 2>&1
  ufw allow "${PORT}/tcp" >/dev/null 2>&1
  echo "Done. Port ${PORT} opened."
else
  echo "Warning: ufw not found. Open port ${PORT}/udp manually."
fi

echo "Starting service..."
systemctl enable hysteria-server >/dev/null 2>&1
systemctl restart hysteria-server
sleep 1
systemctl is-active --quiet hysteria-server \
  || die "Service failed. Check: journalctl -u hysteria-server -n 50"
echo "Done. Hysteria2 is running."

echo "Installing h2..."
curl -fsSL "https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/h2" \
  -o "$MANAGER_PATH" || die "Failed to download h2 from GitHub"
chmod +x "$MANAGER_PATH"
echo "Done. h2 installed to $MANAGER_PATH"

SNI="${MASQ_URL#https://}"; SNI="${SNI%/}"
echo ""

if [ "$AUTH_MODE" = "2" ]; then
  echo "${FIRST_USER}"
  echo "hysteria2://${FIRST_USER}:${FIRST_PASS}@${SERVER_IP}:${PORT}?sni=${SNI}&obfs=salamander&obfs-password=${OBFS_PASS}&insecure=1#${KEY_NAME}"
else
  echo "hysteria2://${AUTH_PASS}@${SERVER_IP}:${PORT}?sni=${SNI}&obfs=salamander&obfs-password=${OBFS_PASS}&insecure=1#${KEY_NAME}"
fi

echo ""
echo "Run 'h2 help' for management commands."
echo ""