# hysteria2-installer

One-command [Hysteria2](https://v2.hysteria.network/) installer with interactive setup and a built-in management tool.

```bash
curl -fsSL https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/install.sh -o install.sh && bash install.sh
```

Installs Hysteria2, generates certificates, configures UFW, enables autostart and installs the `h2` management tool.

### Management

```
h2 status     Service status
h2 key        Connection URI
h2 modify     Change settings
h2 uninstall  Remove everything
h2 help       Command list
```

### Certificate modes

**Simple** — generates a self-signed cert. Quick setup, `insecure=1` is added to the URI automatically. Suitable for personal use when you trust the connection.

**CA** — generates a private CA and signs the server cert with it. No `insecure=1` in URI, but you need to import `ca.crt` on each client once:

- **Windows:** Win+R → `certmgr.msc` → Trusted Root Certification Authorities → Right click → All Tasks → Import
- **Android:** Settings → Security → Install certificate
- **iOS:** Send `ca.crt` to device → install profile → Settings → General → VPN & Device Management → trust it
