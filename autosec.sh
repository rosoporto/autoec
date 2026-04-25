#!/usr/bin/env bash
# =============================================================================
#  AutoSec — автоматическая установка и настройка ufw + fail2ban
#  Использование:
#    wget https://raw.githubusercontent.com/YOUR_USER/YOUR_REPO/main/autosec.sh
#    chmod +x autosec.sh
#    nano autosec.sh   # при необходимости измените настройки ниже
#    sudo ./autosec.sh
# =============================================================================

set -euo pipefail

# =============================================================================
#  НАСТРОЙКИ (измените перед запуском, если нужно)
# =============================================================================

# --- UFW ---
UFW_ENABLE_IPV6="yes"           # "yes" или "no"
UFW_DEFAULT_IN="deny"           # deny / allow / reject
UFW_DEFAULT_OUT="allow"         # deny / allow / reject
UFW_SSH_PORT="22"               # порт SSH (если кастомный — поменяйте)
UFW_HTTP_PORT="80"              # HTTP
UFW_HTTPS_PORT="443"            # HTTPS
UFW_EXTRA_PORTS=""              # доп. порты через запятую, например: "8080,9090"
UFW_ALLOW_PING="yes"            # "yes" — разрешить ping, "no" — запретить

# --- fail2ban ---
F2B_SSH_MAXRETRY="3"            # попыток перед баном
F2B_SSH_FINDTIME="600"          # секунд — окно для подсчёта попыток
F2B_SSH_BANTIME="3600"          # секунд — длительность бана (1 час)
F2B_SSH_ENABLED="true"          # защита SSH
F2B_BACKEND="systemd"           # systemd или auto
F2B_BANACTION="iptables-multiport"

# --- Уведомления (опционально) ---
F2B_SENDMAIL=""                 # email для уведомлений (пусто = отключено)
F2B_SENDMAIL_ON_BAN="no"        # "yes" — слать письмо при бане

# --- Система ---
LOG_FILE="/var/log/autosec_install.log"

# =============================================================================
#  ПРОВЕРКИ
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "[ERROR] Скрипт нужно запускать от root: sudo $0"
        exit 1
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        echo "[ERROR] Не удалось определить дистрибутив"
        exit 1
    fi
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# =============================================================================
#  УСТАНОВКА
# =============================================================================

install_packages() {
    log "=== Установка пакетов ==="
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
                log "[WARN] Неизвестный дистрибутив '$DISTRO', пробуем apt..."
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -qq
                apt-get install -y -qq ufw fail2ban || {
                    echo "[ERROR] Не удалось установить пакеты. Установите ufw и fail2ban вручную."
                    exit 1
                }
            fi
            ;;
    esac
    log "Пакеты установлены"
}

# =============================================================================
#  НАСТРОЙКА UFW
# =============================================================================

configure_ufw() {
    log "=== Настройка UFW ==="

    # IPv6
    if [[ "$UFW_ENABLE_IPV6" == "yes" ]]; then
        sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw
    else
        sed -i 's/^IPV6=.*/IPV6=no/' /etc/default/ufw
    fi

    # Политики по умолчанию
    ufw default "$UFW_DEFAULT_IN" incoming
    ufw default "$UFW_DEFAULT_OUT" outgoing

    # Разрешаем loopback
    ufw allow in on lo
    ufw deny in from 127.0.0.0/8
    ufw deny in from ::1

    # Разрешаем SSH (критично — не потерять доступ!)
    ufw allow "${UFW_SSH_PORT}/tcp"

    # Разрешаем HTTP/HTTPS
    ufw allow "${UFW_HTTP_PORT}/tcp"
    ufw allow "${UFW_HTTPS_PORT}/tcp"

    # Дополнительные порты
    if [[ -n "$UFW_EXTRA_PORTS" ]]; then
        IFS=',' read -ra PORTS <<< "$UFW_EXTRA_PORTS"
        for port in "${PORTS[@]}"; do
            port=$(echo "$port" | tr -d ' ')
            if [[ "$port" =~ ^[0-9]+(/tcp|/udp)?$ ]]; then
                ufw allow "$port"
                log "  Доп. порт разрешён: $port"
            fi
        done
    fi

    # Ping (ICMP)
    if [[ "$UFW_ALLOW_PING" == "yes" ]]; then
        # Разрешаем ICMP echo-request
        sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT/d' /etc/ufw/before.rules
        sed -i '/-A ufw-before-input -p icmp --icmp-type echo-request -j DROP/a -A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT' /etc/ufw/before.rules
        # Убедимся, что правило есть (добавим в начало цепочки, если не было)
        if ! grep -q "icmp-type echo-request -j ACCEPT" /etc/ufw/before.rules; then
            sed -i '/-A ufw-before-input -p icmp --icmp-type destination-unreachable -j ACCEPT/a -A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT' /etc/ufw/before.rules
        fi
    fi

    # Включаем ufw
    echo "y" | ufw enable
    ufw reload

    log "UFW настроен и активирован"
    ufw status verbose | tee -a "$LOG_FILE"
}

# =============================================================================
#  НАСТРОЙКА fail2ban
# =============================================================================

configure_fail2ban() {
    log "=== Настройка fail2ban ==="

    # Создаём jail.local
    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Используемый бэкенд
backend = $F2B_BACKEND
banaction = $F2B_BANACTION
# Отправка почты (если настроено)
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

    # Перезапускаем fail2ban
    systemctl restart fail2ban
    systemctl enable fail2ban

    # Проверяем статус
    sleep 2
    if systemctl is-active --quiet fail2ban; then
        log "fail2ban активен"
    else
        log "[WARN] fail2ban не запустился, проверьте journalctl -u fail2ban"
    fi

    # Выводим статус jail
    fail2ban-client status sshd 2>/dev/null | tee -a "$LOG_FILE" || true
}

# =============================================================================
#  ФИНАЛЬНАЯ ПРОВЕРКА
# =============================================================================

final_check() {
    log "=== Финальная проверка ==="

    local errors=0

    if ! systemctl is-active --quiet ufw; then
        log "[WARN] UFW не активен в systemctl (нормально для ufw, проверяем статус)"
    fi

    if ! ufw status | grep -q "Status: active"; then
        log "[ERROR] UFW не активен!"
        errors=$((errors + 1))
    fi

    if ! systemctl is-active --quiet fail2ban; then
        log "[ERROR] fail2ban не запущен!"
        errors=$((errors + 1))
    fi

    # Проверяем, что SSH-порт открыт
    if ! ufw status | grep -q "${UFW_SSH_PORT}/tcp.*ALLOW"; then
        log "[ERROR] SSH-порт ${UFW_SSH_PORT} не разрешён в UFW!"
        errors=$((errors + 1))
    fi

    echo ""
    echo "============================================================================="
    if [[ $errors -eq 0 ]]; then
        echo "  🎉  Congratulations! Сервер защищён."
        echo "============================================================================="
        echo ""
        echo "  UFW:     активен, порты ${UFW_SSH_PORT}(SSH), ${UFW_HTTP_PORT}(HTTP), ${UFW_HTTPS_PORT}(HTTPS)"
        [[ -n "$UFW_EXTRA_PORTS" ]] && echo "           + дополнительные: $UFW_EXTRA_PORTS"
        echo "  fail2ban: активен, sshd защищён"
        echo "           maxretry=${F2B_SSH_MAXRETRY}, findtime=${F2B_SSH_FINDTIME}s, bantime=${F2B_SSH_BANTIME}s"
        echo ""
        echo "  Лог установки: $LOG_FILE"
        echo "  Проверить статус: sudo ufw status verbose"
        echo "                    sudo fail2ban-client status sshd"
        echo "============================================================================="
        return 0
    else
        echo "  ⚠️  Обнаружено $errors проблем. Проверьте лог: $LOG_FILE"
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
    echo "  ║           AutoSec — автоматическая защита сервера             ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    detect_distro
    log "Дистрибутив: $DISTRO"

    install_packages
    configure_ufw
    configure_fail2ban
    final_check
}

main "$@"
