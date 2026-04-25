# AutoSec

> One-command server hardening: automatic install and configure `ufw` + `fail2ban`.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Quick Start

```bash
# 1. Download
wget https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/autosec.sh

# 2. (Optional) Edit settings
nano autosec.sh

# 3. Run
chmod +x autosec.sh
sudo ./autosec.sh
```

At the end you'll see:

```
🎉  Congratulations! Server is secured.
```

---

## What It Does

| Component | Action |
|-----------|--------|
| **UFW** | Installs, sets default policies, opens required ports, enables firewall |
| **fail2ban** | Installs, creates `jail.local`, protects SSH from brute-force, starts service |
| **Validation** | Verifies everything is active and prints a final report |

---

## Supported Distros

- **Debian** / **Ubuntu**
- **RHEL** / **CentOS** / **Rocky Linux** / **AlmaLinux**
- **Fedora**
- **Arch Linux** / **Manjaro**
- **Alpine Linux**

---

## Configuration

All settings are at the top of the script. Edit before running.

### UFW Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `UFW_ENABLE_IPV6` | `yes` | Enable IPv6 support |
| `UFW_DEFAULT_IN` | `deny` | Default incoming policy (`deny` / `allow` / `reject`) |
| `UFW_DEFAULT_OUT` | `allow` | Default outgoing policy |
| `UFW_SSH_PORT` | `22` | SSH port |
| `UFW_HTTP_PORT` | `80` | HTTP port |
| `UFW_HTTPS_PORT` | `443` | HTTPS port |
| `UFW_EXTRA_PORTS` | `""` | Extra ports, comma-separated, e.g. `"8080,9090"` |
| `UFW_ALLOW_PING` | `yes` | Allow ICMP echo-request (ping) |

### fail2ban Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `F2B_SSH_MAXRETRY` | `3` | Failed login attempts before ban |
| `F2B_SSH_FINDTIME` | `600` | Time window for counting attempts (seconds) |
| `F2B_SSH_BANTIME` | `3600` | Ban duration (seconds) |
| `F2B_SSH_ENABLED` | `true` | Enable SSH protection |
| `F2B_BACKEND` | `systemd` | Logging backend (`systemd` or `auto`) |
| `F2B_BANACTION` | `iptables-multiport` | Ban action |
| `F2B_SENDMAIL` | `""` | Notification email (empty = disabled) |
| `F2B_SENDMAIL_ON_BAN` | `no` | Send email on every ban |

### Custom Config Example

```bash
# Custom SSH port + extra app port
UFW_SSH_PORT="2222"
UFW_EXTRA_PORTS="3000,8080"

# Strict fail2ban: 24h ban after 2 attempts
F2B_SSH_MAXRETRY="2"
F2B_SSH_BANTIME="86400"
```

---

## Post-Install Verification

```bash
# Firewall status
sudo ufw status verbose

# fail2ban status
sudo systemctl status fail2ban
sudo fail2ban-client status sshd

# Installation log
cat /var/log/autosec_install.log
```

---

## Troubleshooting

### Script requires root
```bash
sudo ./autosec.sh
```

### UFW not found in repo (CentOS/RHEL)
In rare cases `ufw` is missing. Enable EPEL first:
```bash
sudo dnf install epel-release
sudo ./autosec.sh
```

### Lost SSH access
The script **always** opens the SSH port (`UFW_SSH_PORT`) before enabling UFW. If you changed the SSH port manually after OS install, make sure `UFW_SSH_PORT` matches the actual port in `/etc/ssh/sshd_config`.

---

## License

MIT © 2026
