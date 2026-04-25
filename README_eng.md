# AutoSec

> Bash script for automatic installation and configuration of `ufw` + `fail2ban` on a fresh server.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Shell](https://img.shields.io/badge/shell-bash-89e051)

---

## Requirements

- A supported Linux distribution (see [Supported Distros](#supported-distros))
- `bash` 4.0+
- `sudo` or root access
- `wget` or `curl` to download the script

---

## Quick Start

**Option 1 — wget:**

```bash
# 1. Download the script
wget https://raw.githubusercontent.com/rosoporto/autosec/main/autosec.sh

# 2. (Optional) Edit settings
nano autosec.sh

# 3. Run
chmod +x autosec.sh
sudo ./autosec.sh
```

**Option 2 — git clone:**

```bash
git clone https://github.com/rosoporto/autosec.git
cd autosec
sudo ./autosec.sh
```

When finished, you'll see:

```
🎉  Congratulations! Server is secured.
```

---

## What It Does

| Component | Action |
| --- | --- |
| **UFW** | Installs, sets default policies, opens required ports, enables the firewall |
| **fail2ban** | Installs, creates `jail.local`, protects SSH from brute-force attacks, starts the service |
| **Validation** | Verifies everything is running and prints a final report |

---

## Supported Distros

- **Debian** / **Ubuntu**
- **RHEL** / **CentOS** / **Rocky Linux** / **AlmaLinux**
- **Fedora**
- **Arch Linux** / **Manjaro**
- **Alpine Linux** ⚠️ — uses OpenRC instead of systemd; set `F2B_BACKEND="auto"` before running

---

## Configuration

All settings are at the top of the script. Edit them before running.

### UFW

| Variable | Default | Description |
| --- | --- | --- |
| `UFW_ENABLE_IPV6` | `yes` | Enable IPv6 support |
| `UFW_DEFAULT_IN` | `deny` | Default incoming policy (`deny` / `allow` / `reject`) |
| `UFW_DEFAULT_OUT` | `allow` | Default outgoing policy |
| `UFW_SSH_PORT` | `22` | SSH port |
| `UFW_HTTP_PORT` | `80` | HTTP port |
| `UFW_HTTPS_PORT` | `443` | HTTPS port |
| `UFW_EXTRA_PORTS` | `""` | Additional ports, comma-separated, e.g. `"8080,9090"` |
| `UFW_ALLOW_PING` | `yes` | Allow ICMP echo-request (ping) |

### fail2ban

| Variable | Default | Description |
| --- | --- | --- |
| `F2B_SSH_MAXRETRY` | `3` | Failed login attempts before ban |
| `F2B_SSH_FINDTIME` | `600` | Time window for counting attempts (seconds) |
| `F2B_SSH_BANTIME` | `3600` | Ban duration (seconds) |
| `F2B_SSH_ENABLED` | `true` | Enable SSH protection |
| `F2B_BACKEND` | `systemd` | Logging backend (`systemd` or `auto`; use `auto` on Alpine) |
| `F2B_BANACTION` | `iptables-multiport` | Ban action |
| `F2B_SENDMAIL` | `""` | Notification email (empty = disabled) |
| `F2B_SENDMAIL_ON_BAN` | `no` | Send an email on every ban |

### Custom Configuration Example

```bash
# Non-standard SSH port + extra port for an application
UFW_SSH_PORT="2222"
UFW_EXTRA_PORTS="3000,8080"

# Strict fail2ban: 24-hour ban after 2 failed attempts
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

### UFW not found in repository (CentOS/RHEL)

In rare cases `ufw` is missing from the default repos. Enable EPEL and re-run:

```bash
sudo dnf install epel-release
sudo ./autosec.sh
```

### Lost SSH access

The script **always** opens the SSH port (`UFW_SSH_PORT`) before enabling UFW. If you changed the SSH port manually after the OS install, make sure `UFW_SSH_PORT` matches the actual port in `/etc/ssh/sshd_config`.

### fail2ban banned my own IP

Unban an IP manually:

```bash
sudo fail2ban-client unban <IP>
```

Or unban from a specific jail:

```bash
sudo fail2ban-client set sshd unbanip <IP>
```

### Alpine Linux: fail2ban fails to start

Alpine uses OpenRC, not systemd. Set the backend before running the script:

```bash
F2B_BACKEND="auto"
```

---

## License

MIT © 2026
