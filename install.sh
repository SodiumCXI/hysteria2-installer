#!/bin/bash

set -euo pipefail

[ "$EUID" -ne 0 ] && { echo "Error: run as root"; exit 1; }

MANAGER_PATH="/usr/local/bin/h2"
MANAGER_URL="https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/h2"

curl -fsSL "$MANAGER_URL" -o "${MANAGER_PATH}.new" \
  || { echo "Error: failed to download h2 from GitHub"; exit 1; }
chmod +x "${MANAGER_PATH}.new"
mv -f "${MANAGER_PATH}.new" "$MANAGER_PATH"

if [ -f "/etc/hysteria/.state" ]; then
  exec "$MANAGER_PATH" update
fi

exec "$MANAGER_PATH" install </dev/tty
