#!/bin/bash

set -euo pipefail

[ "$EUID" -ne 0 ] && { echo "error: run as root"; exit 1; }

MANAGER_PATH="/usr/local/bin/h2"
STATE_FILE="/etc/hysteria/.state"
CONFIG_FILE="/etc/hysteria/config.yaml"

rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; true; }
die()  { echo "error: $*"; exit 1; }

if command -v hysteria &>/dev/null && [ -f "$CONFIG_FILE" ]; then
  echo ""
  echo "hysteria2 is already installed."
  echo "use 'h2 modify' to change settings or 'h2 uninstall' to remove."
  echo ""
  exit 0
fi

SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)
[ -z "$SERVER_IP" ] && die "could not detect external IP"

echo ""
echo "hysteria2 setup"
echo "───────────────"

read -rp "server ip/hostname   [${SERVER_IP}]: " _in; SERVER_IP="${_in:-$SERVER_IP}"
read -rp "port                 [443]: "           _in; PORT="${_in:-443}"
read -rp "auth password        [random]: "        _in; AUTH_PASS="${_in:-$(rand 16)}"
read -rp "obfs password        [random]: "        _in; OBFS_PASS="${_in:-$(rand 16)}"
read -rp "masquerade url       [https://microsoft.com/]: " _in; MASQ_URL="${_in:-https://microsoft.com/}"

echo ""
echo "certificate mode:"
echo "  1) simple — self-signed, insecure=1 in uri"
echo "  2) ca     — own CA, import cert on client, no insecure"
echo ""
read -rp "choose [1/2] [1]: " _in; CERT_MODE="${_in:-1}"
echo ""

echo "[ 1/5 ] installing hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/) >/dev/null 2>&1
echo "        done: $(hysteria version 2>/dev/null | head -1)"

echo "[ 2/5 ] generating certificates..."
mkdir -p /etc/hysteria
chown hysteria:hysteria /etc/hysteria
chmod 750 /etc/hysteria

if [ "$CERT_MODE" = "2" ]; then
  read -rp "ca name              [MyVPN-CA]: " _in; CA_NAME="${_in:-MyVPN-CA}"

  openssl genrsa -out /etc/hysteria/ca.key 2048 2>/dev/null
  openssl req -x509 -new -nodes \
    -key /etc/hysteria/ca.key -sha256 -days 36500 \
    -out /etc/hysteria/ca.crt \
    -subj "/CN=${CA_NAME}" 2>/dev/null
  openssl genrsa -out /etc/hysteria/server.key 2048 2>/dev/null
  openssl req -new \
    -key /etc/hysteria/server.key \
    -out /etc/hysteria/server.csr \
    -subj "/CN=${SERVER_IP}" 2>/dev/null
  openssl x509 -req \
    -in /etc/hysteria/server.csr \
    -CA /etc/hysteria/ca.crt -CAkey /etc/hysteria/ca.key \
    -CAcreateserial -out /etc/hysteria/server.crt \
    -days 36500 -sha256 2>/dev/null
  rm -f /etc/hysteria/server.csr
  echo "        done: ca-signed"
else
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 36500 -subj "/CN=localhost" 2>/dev/null
  echo "        done: self-signed"
fi

chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
chmod 600 /etc/hysteria/server.key
chmod 644 /etc/hysteria/server.crt

echo "[ 3/5 ] writing config..."
cat > "$CONFIG_FILE" <<EOF
listen: :${PORT}

tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key

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
EOF

cat > "$STATE_FILE" <<EOF
SERVER_IP="${SERVER_IP}"
PORT="${PORT}"
AUTH_PASS="${AUTH_PASS}"
OBFS_PASS="${OBFS_PASS}"
MASQ_URL="${MASQ_URL}"
CERT_MODE="${CERT_MODE}"
EOF
chmod 600 "$STATE_FILE"
echo "        done: $CONFIG_FILE"

echo "[ 4/5 ] configuring firewall..."
if command -v ufw &>/dev/null; then
  ufw allow "${PORT}/udp" >/dev/null 2>&1
  ufw allow "${PORT}/tcp" >/dev/null 2>&1
  echo "        done: port ${PORT} opened"
else
  echo "        warning: ufw not found — open port ${PORT}/udp manually"
fi

echo "[ 5/5 ] starting service..."
systemctl enable hysteria-server >/dev/null 2>&1
systemctl restart hysteria-server
sleep 1
systemctl is-active --quiet hysteria-server \
  || die "service failed — check: journalctl -u hysteria-server -n 50"
echo "        done: hysteria-server running"

curl -fsSL "https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/h2" \
  -o "$MANAGER_PATH" || die "failed to download h2 from github"
chmod +x "$MANAGER_PATH"

URI="hysteria2://${AUTH_PASS}@${SERVER_IP}:${PORT}?obfs=salamander&obfs-password=${OBFS_PASS}"
[ "$CERT_MODE" != "2" ] && URI="${URI}&insecure=1"

echo ""
echo "───────────────────────────────────────────────────────"
echo "ip:            ${SERVER_IP}"
echo "port:          ${PORT}"
echo "auth password: ${AUTH_PASS}"
echo "obfs password: ${OBFS_PASS}"
echo ""
echo "uri:"
echo "${URI}"
echo "───────────────────────────────────────────────────────"

if [ "$CERT_MODE" = "2" ]; then
  echo ""
  echo "ca certificate (save as hysteria-ca.crt and import on client):"
  echo "───────────────────────────────────────────────────────"
  cat /etc/hysteria/ca.crt
  echo "───────────────────────────────────────────────────────"
  echo ""
  echo "windows: win+r → certmgr.msc → trusted root certification authorities"
  echo "         → right click → all tasks → import → select hysteria-ca.crt"
fi

echo ""
echo "manage with: h2 help"
echo ""
