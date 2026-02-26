#!/bin/bash
set -euo pipefail

[ "$EUID" -ne 0 ] && { echo "Error: run as root"; exit 1; }

MANAGER_PATH="/usr/local/bin/h2"
STATE_FILE="/etc/hysteria/.state"
CONFIG_FILE="/etc/hysteria/config.yaml"

rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; true; }
die()  { echo "Error: $*"; exit 1; }

if command -v hysteria &>/dev/null && [ -f "$CONFIG_FILE" ]; then
  echo "Hysteria2 is already installed. Use 'h2 modify' or 'h2 uninstall'."
  exit 0
fi

SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || curl -s --max-time 5 https://ifconfig.me)
[ -z "$SERVER_IP" ] && die "Could not detect external IP"

echo ""
echo "Hysteria2 Setup"
echo ""

read -rp "Port [443]: " _in; PORT="${_in:-443}"
read -rp "Auth password [random]: " _in; AUTH_PASS="${_in:-$(rand 16)}"
read -rp "Obfs password [random]: " _in; OBFS_PASS="${_in:-$(rand 16)}"
read -rp "SNI [google.com]: " _in; MASQ_URL="https://${_in:-google.com}/"

echo "Certificate mode:"
echo "  1 Simple — self-signed, insecure=1 in URI"
echo "  2 CA — own CA, import cert on client, no insecure"
read -rp "Choose [1/2]: " _in; CERT_MODE="${_in:-1}"
echo ""

echo "Installing Hysteria2..."
bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | grep -v "^$" | sed '/Congratulation/q'

echo "Generating certificates..."
mkdir -p /etc/hysteria
chown hysteria:hysteria /etc/hysteria
chmod 750 /etc/hysteria

if [ "$CERT_MODE" = "2" ]; then
  read -rp "CA name [MyVPN-CA]: " _in; CA_NAME="${_in:-MyVPN-CA}"
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
  echo "Done. Mode: CA-signed"
else
  openssl req -x509 -nodes -newkey rsa:2048 \
    -keyout /etc/hysteria/server.key \
    -out /etc/hysteria/server.crt \
    -days 36500 -subj "/CN=localhost" 2>/dev/null
  echo "Done. Mode: Self-signed"
fi

chown hysteria:hysteria /etc/hysteria/server.key /etc/hysteria/server.crt
chmod 600 /etc/hysteria/server.key
chmod 644 /etc/hysteria/server.crt

echo "Writing config..."
cat > "$CONFIG_FILE" <<CONF
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
CONF

cat > "$STATE_FILE" <<STATE
SERVER_IP="${SERVER_IP}"
PORT="${PORT}"
AUTH_PASS="${AUTH_PASS}"
OBFS_PASS="${OBFS_PASS}"
MASQ_URL="${MASQ_URL}"
CERT_MODE="${CERT_MODE}"
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
URI="hysteria2://${AUTH_PASS}@${SERVER_IP}:${PORT}?sni=${SNI}&obfs=salamander&obfs-password=${OBFS_PASS}"
[ "$CERT_MODE" != "2" ] && URI="${URI}&insecure=1"

echo ""
echo "IP    $SERVER_IP"
echo "Port  $PORT"
echo "Auth  $AUTH_PASS"
echo "Obfs  $OBFS_PASS"
echo ""
echo "$URI"

if [ "$CERT_MODE" = "2" ]; then
  echo ""
  echo "CA Certificate — save as hysteria-ca.crt and import on client:"
  echo ""
  cat /etc/hysteria/ca.crt
fi

echo ""
echo "Run 'h2 help' for management commands."
echo ""