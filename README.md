# hysteria2-installer

```bash
curl -fsSL https://raw.githubusercontent.com/SodiumCXI/hysteria2-installer/main/install.sh -o install.sh && bash install.sh
```

Installs Hysteria2, generates access keys, configures UFW, enables autostart and installs the `h2` management tool.

### Management

```
h2 status     Service status
h2 key        Connection URI
h2 modify     Change settings
h2 useradd    Add user
h2 userdel    Delete user
h2 userlist   List users
h2 uninstall  Remove everything
```

### Authentication modes

- **Single password** - generates one shared access key for all clients.
Best for personal use or a small trusted group.
- **Users** - generates a separate access key for each user.
Allows managing clients individually without affecting others.
