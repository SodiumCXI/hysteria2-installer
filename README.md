# hysteria2-installer

One-command [Hysteria2](https://v2.hysteria.network/) installer for Debian/Ubuntu with interactive setup and a built-in management tool.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/install.sh -o install.sh && bash install.sh
```

Installs Hysteria2, generates certificates, configures UFW, enables autostart and installs the `h2` management tool.

## Management

```
h2 status     Service status
h2 key        Connection URI
h2 modify     Change settings
h2 uninstall  Remove everything
h2 help       Command list
```

## Certificate modes

| Mode | Description |
|------|-------------|
| Simple | Self-signed cert, `insecure=1` in URI. No extra steps. |
| CA | Own CA, signed server cert. Import `ca.crt` on client — no `insecure` needed. |
