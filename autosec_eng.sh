#!/usr/bin/env bash
# =============================================================================
#  AutoSec — Automatic ufw + fail2ban setup for a fresh server
#  Usage:
#    wget https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/autosec.sh
#    chmod +x autosec.sh
#    nano autosec.sh   # edit settings below if needed
#    sudo ./autosec.sh
# =============================================================================

set -euo pipefail

# =============================================================================
#  SETTINGS (change before running if needed)
# =============================================================================

# --- UFW ---
UFW_ENABLE_IPV6="yes"           # "yes" or "no"
UFW_DEFAULT_IN="deny"           # deny / allow / reject
UFW_DEFAULT_OUT="allow"         # deny / allow / reject
UFW_SSH_PORT="22"               # SSH port (change if custom)
UFW_HTTP_PORT="80"              # HTTP
UFW_HTTPS_PORT="443"            # HTTPS
UFW_EXTRA_PORTS=""              # extra ports comma-separated, e.g. "8080,9090"
UFW_ALLOW_PING="yes"            # "yes" — allow ping, "no" — deny

# --- fail2ban ---
F2B_SSH_MAXRETRY="3"            # attempts before ban
F2B_SSH_FINDTIME="600"          # seconds — window for counting attempts
F2B_SSH_BANTIME="3600"          # seconds — ban duration (1 hour)
F2B_SSH_ENABLED="true"          # SSH protection
F2B_BACKEND="systemd"           # systemd or auto
F2B_BANACTION="iptables-multiport"

# --- Notifications (optional) ---
F2B_SENDMAIL=""                 # email for notifications (empty = disabled)
F2B_SENDMAIL_ON_BAN="no"        # "yes" — send email on ban

# --- System ---
LOG_FILE="/var/log/autosec_install.log"

# =============================================================================
#  CHECKS
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] Run as root: sudo $0"
        exit 1
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        echo "[ERROR] Could not detect distro"
        exit 1
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# =============================================================================
#  INSTALLATION
# =============================================================================

install_packages() {
    log "=== Installing packages ==="
    case "$DISTRO" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq
            apt-get install -y -qq ufw fail2ban
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf install -y ufw fail2ban
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm ufw fail2ban
            ;;
        alpine)
            apk add --no-cache ufw fail2ban
            ;;
        *)
            if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq
                apt-get install -y -qq ufw fail2ban
            elif [[ "$DISTRO_LIKE" == *"rhel"* ]] || [[ "$DISTRO_LIKE" == *"fedora"* ]]; then
                dnf install -y ufw fail2ban
            else
                log "[WARN] Unknown distro '$DISTRO', trying apt..."
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq
                apt-get install -y -qq ufw fail2ban || {
                    echo "[ERROR] Failed to install packages. Install ufw and fail2ban manually."
                    exit 1
                }
            fi
            ;;
    esac
    log "Packages installed"
}

# =============================================================================
#  UFW CONFIGURATION
# =============================================================================

configure_ufw() {
    log "=== Configuring UFW ==="

    # IPv6
    if [[ "$UFW_ENABLE_IPV6" == "yes" ]]; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
        sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    fi

    # Default policies
    ufw default "$UFW_DEFAULT_IN" incoming
    ufw default "$UFW_DEFAULT_OUT" outgoing

    # Allow loopback
    ufw allow in on lo
    ufw deny in from 127.0.0.0/8
    ufw deny in from ::1

    # Allow SSH (critical — don't lock yourself out!)
    ufw allow "${UFW_SSH_PORT}/tcp"

    # Allow HTTP/HTTPS
    ufw allow "${UFW_HTTP_PORT}/tcp"
    ufw allow "${UFW_HTTPS_PORT}/tcp"

    # Extra ports
    if [[ -n "$UFW_EXTRA_PORTS" ]]; then
        IFS=',' read -ra PORTS <<< "$UFW_EXTRA_PORTS"
        for port in "${PORTS[@]}"; do
            port=$(echo "$port" | tr -d ' ')
            if [[ "$port" =~ ^[0-9]+(/tcp|/udp)?$ ]]; then
                ufw allow "$port"
                log "  Extra port allowed: $port"
            fi
        done
    fi

    # Ping (ICMP)
    if [[ "$UFW_ALLOW_PING" == "yes" ]]; then
        sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/d' /etc/ufw/before.rules
        sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT' /etc/ufw/before.rules
        if ! grep -q "icmp-type echo-request -j ACCEPT" /etc/ufw/before.rules; then
            sed -i '/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/a -A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT' /etc/ufw/before.rules
        fi
    fi

    # Enable UFW
    echo "y" | ufw enable
    ufw reload

    log "UFW configured and active"
    ufw status verbose | tee -a "$LOG_FILE"
}

# =============================================================================
#  fail2ban CONFIGURATION
# =============================================================================

configure_fail2ban() {
    log "=== Configuring fail2ban ==="

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
backend = $F2B_BACKEND
banaction = $F2B_BANACTION
EOF

    if [[ -n "$F2B_SENDMAIL" ]]; then
        cat >> /etc/fail2ban/jail.local <<EOF
destemail = $F2B_SENDMAIL
sender = fail2ban@localhost
mta = sendmail
EOF
        if [[ "$F2B_SENDMAIL_ON_BAN" == "yes" ]]; then
            echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
        fi
    fi

    cat >> /etc/fail2ban/jail.local <<EOF

[sshd]
enabled = $F2B_SSH_ENABLED
port = $UFW_SSH_PORT
filter = sshd
logpath = %(sshd_log)s
maxretry = $F2B_SSH_MAXRETRY
findtime = $F2B_SSH_FINDTIME
bantime = $F2B_SSH_BANTIME
EOF

    systemctl restart fail2ban
    systemctl enable fail2ban

    sleep 2
    if systemctl is-active --quiet fail2ban; then
        log "fail2ban is active"
    else
        log "[WARN] fail2ban failed to start, check: journalctl -u fail2ban"
    fi

    fail2ban-client status sshd 2>/dev/null | tee -a "$LOG_FILE" || true
}

# =============================================================================
#  FINAL CHECK
# =============================================================================

final_check() {
    log "=== Final check ==="

    local errors=0

    if ! systemctl is-active --quiet ufw; then
        log "[WARN] UFW not active in systemctl (normal for ufw, checking status)"
    fi

    if ! ufw status | grep -q "Status: active"; then
        log "[ERROR] UFW is not active!"
        errors=$((errors + 1))
    fi

    if ! systemctl is-active --quiet fail2ban; then
        log "[ERROR] fail2ban is not running!"
        errors=$((errors + 1))
    fi

    if ! ufw status | grep -q "${UFW_SSH_PORT}/tcp.*ALLOW"; then
        log "[ERROR] SSH port ${UFW_SSH_PORT} is not allowed in UFW!"
        errors=$((errors + 1))
    fi

    echo ""
    echo "============================================================================="
    if [[ $errors -eq 0 ]]; then
        echo "  🎉  Congratulations! Server is secured."
        echo "============================================================================="
        echo ""
        echo "  UFW:     active, ports ${UFW_SSH_PORT}(SSH), ${UFW_HTTP_PORT}(HTTP), ${UFW_HTTPS_PORT}(HTTPS)"
        [[ -n "$UFW_EXTRA_PORTS" ]] && echo "           + extra: $UFW_EXTRA_PORTS"
        echo "  fail2ban: active, sshd protected"
        echo "           maxretry=${F2B_SSH_MAXRETRY}, findtime=${F2B_SSH_FINDTIME}s, bantime=${F2B_SSH_BANTIME}s"
        echo ""
        echo "  Install log: $LOG_FILE"
        echo "  Check status: sudo ufw status verbose"
        echo "                sudo fail2ban-client status sshd"
        echo "============================================================================="
        return 0
    else
        echo "  ⚠️  Found $errors issue(s). Check log: $LOG_FILE"
        echo "============================================================================="
        return 1
    fi
}

# =============================================================================
#  MAIN
# =============================================================================

main() {
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║           AutoSec — Automatic Server Hardening                ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    detect_distro
    log "Distro: $DISTRO"

    install_packages
    configure_ufw
    configure_fail2ban
    final_check
}

main "$@"
