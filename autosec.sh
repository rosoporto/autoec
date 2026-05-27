#!/usr/bin/env bash
# =============================================================================
#  AutoSec v0.2 — первичная защита сервера (UFW + fail2ban)
#
#  Назначение: настройка firewall и защиты от brute-force СРАЗУ ПОСЛЕ
#  покупки сервера, ДО перехода на SSH-ключи. Скрипт НЕ трогает sshd,
#  чтобы не сломать вход по паролю.
#
#  После перехода на ключи запустите отдельный этап SSH hardening.
#
#  Использование:
#    chmod +x autosec.sh
#    nano autosec.sh   # при необходимости измените настройки ниже
#    sudo ./autosec.sh
# =============================================================================

set -euo pipefail

# =============================================================================
#  НАСТРОЙКИ
# =============================================================================

# --- Система ---
DO_SYSTEM_UPGRADE="yes"         # "yes" — выполнить apt/dnf upgrade перед установкой
LOG_FILE="/var/log/autosec_install.log"

# --- UFW ---
UFW_ENABLE_IPV6="yes"           # "yes" / "no"
UFW_DEFAULT_IN="deny"           # deny / allow / reject
UFW_DEFAULT_OUT="allow"         # deny / allow / reject
UFW_SSH_PORT="22"               # порт SSH (см. также AUTODETECT_SSH_PORT)
AUTODETECT_SSH_PORT="yes"       # "yes" — попытаться определить реальный порт sshd
UFW_HTTP_PORT="80"              # HTTP
UFW_HTTPS_PORT="443"            # HTTPS
UFW_EXTRA_PORTS=""              # доп. порты через запятую: "8080,9090/udp"
UFW_ALLOW_PING="yes"            # "yes" — разрешить ping, "no" — запретить

# --- fail2ban ---
F2B_SSH_MAXRETRY="3"            # попыток перед баном
F2B_SSH_FINDTIME="600"          # окно (сек) для подсчёта попыток
F2B_SSH_BANTIME="3600"          # длительность бана (сек, 1 час)
F2B_SSH_ENABLED="true"          # защита SSH
F2B_BACKEND="systemd"           # systemd / auto
F2B_BANACTION="iptables-multiport"

# --- Уведомления (опционально) ---
F2B_SENDMAIL=""                 # email для уведомлений (пусто = отключено)
F2B_SENDMAIL_ON_BAN="no"        # "yes" — слать письмо при бане

# =============================================================================
#  УТИЛИТЫ
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

err() {
    echo "[ERROR] $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE" 2>/dev/null || true
}

backup_file() {
    # Создаёт .bak.<timestamp> рядом с файлом, если файл существует.
    local f="$1"
    if [[ -f "$f" ]]; then
        cp -a "$f" "${f}.bak.$(date +%s)"
        log "  Бэкап: ${f}.bak.<timestamp>"
    fi
}

# =============================================================================
#  ПРОВЕРКИ
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Скрипт нужно запускать от root: sudo $0"
        exit 1
    fi
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_LIKE="${ID_LIKE:-}"
    else
        err "Не удалось определить дистрибутив (нет /etc/os-release)"
        exit 1
    fi
}

autodetect_ssh_port() {
    # Пробует прочитать реальный Port sshd (берёт первый, если несколько).
    # Если не удалось — оставляет UFW_SSH_PORT как есть.
    [[ "$AUTODETECT_SSH_PORT" != "yes" ]] && return 0
    if command -v sshd &>/dev/null; then
        local detected
        detected=$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}' || true)
        if [[ -n "${detected:-}" && "$detected" != "$UFW_SSH_PORT" ]]; then
            log "Автоопределение SSH-порта: sshd слушает $detected (было $UFW_SSH_PORT)"
            UFW_SSH_PORT="$detected"
        fi
    fi
}

validate_config() {
    if ! [[ "$UFW_SSH_PORT" =~ ^[0-9]+$ ]] || \
       [[ "$UFW_SSH_PORT" -lt 1 || "$UFW_SSH_PORT" -gt 65535 ]]; then
        err "UFW_SSH_PORT должен быть числом 1–65535, сейчас: '$UFW_SSH_PORT'"
        exit 1
    fi
    for p in "$UFW_HTTP_PORT" "$UFW_HTTPS_PORT"; do
        if ! [[ "$p" =~ ^[0-9]+$ ]] || [[ "$p" -lt 1 || "$p" -gt 65535 ]]; then
            err "Порт '$p' некорректен"
            exit 1
        fi
    done
}

# =============================================================================
#  ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ПАКЕТОВ
# =============================================================================

system_upgrade() {
    [[ "$DO_SYSTEM_UPGRADE" != "yes" ]] && { log "Пропуск apt/dnf upgrade (DO_SYSTEM_UPGRADE=no)"; return 0; }
    log "=== Обновление системы ==="
    case "$DISTRO" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -qq || { err "apt-get update не удался"; exit 1; }
            apt-get upgrade -y -qq -o Dpkg::Options::="--force-confold" \
                                   -o Dpkg::Options::="--force-confdef" \
                || { err "apt-get upgrade не удался"; exit 1; }
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf upgrade -y || { err "dnf upgrade не удался"; exit 1; }
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm || { err "pacman -Syu не удался"; exit 1; }
            ;;
        alpine)
            apk update && apk upgrade || { err "apk upgrade не удался"; exit 1; }
            ;;
        *)
            log "[WARN] Обновление пропущено: неизвестный дистрибутив '$DISTRO'"
            ;;
    esac
    log "Система обновлена"
}

install_packages() {
    log "=== Установка пакетов (ufw, fail2ban) ==="
    case "$DISTRO" in
        ubuntu|debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get install -y -qq ufw fail2ban
            ;;
        fedora|rhel|centos|rocky|almalinux)
            dnf install -y ufw fail2ban
            ;;
        arch|manjaro)
            pacman -S --noconfirm --needed ufw fail2ban
            ;;
        alpine)
            apk add --no-cache ufw fail2ban
            ;;
        *)
            if [[ "$DISTRO_LIKE" == *"debian"* ]]; then
                export DEBIAN_FRONTEND=noninteractive
                apt-get install -y -qq ufw fail2ban
            elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* ]]; then
                dnf install -y ufw fail2ban
            else
                err "Неизвестный дистрибутив '$DISTRO'. Установите ufw и fail2ban вручную."
                exit 1
            fi
            ;;
    esac
    log "Пакеты установлены"
}

# =============================================================================
#  НАСТРОЙКА UFW
# =============================================================================

configure_icmp() {
    # Включает/выключает ICMP echo-request через before.rules. Идемпотентно.
    local rules_v4="/etc/ufw/before.rules"
    local rules_v6="/etc/ufw/before6.rules"
    [[ -f "$rules_v4" ]] || { log "[WARN] $rules_v4 не найден — пропуск ICMP-настройки"; return 0; }

    backup_file "$rules_v4"
    [[ -f "$rules_v6" ]] && backup_file "$rules_v6"

    if [[ "$UFW_ALLOW_PING" == "yes" ]]; then
        # Убедимся, что echo-request = ACCEPT (дефолт Ubuntu/Debian).
        sed -i 's|^-A ufw-before-input -p icmp --icmp-type echo-request -j DROP|-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT|' "$rules_v4"
        [[ -f "$rules_v6" ]] && \
            sed -i 's|^-A ufw6-before-input -p ipv6-icmp --icmpv6-type echo-request -j DROP|-A ufw6-before-input -p ipv6-icmp --icmpv6-type echo-request -j ACCEPT|' "$rules_v6"
        log "ICMP echo-request: ACCEPT"
    else
        sed -i 's|^-A ufw-before-input -p icmp --icmp-type echo-request -j ACCEPT|-A ufw-before-input -p icmp --icmp-type echo-request -j DROP|' "$rules_v4"
        [[ -f "$rules_v6" ]] && \
            sed -i 's|^-A ufw6-before-input -p ipv6-icmp --icmpv6-type echo-request -j ACCEPT|-A ufw6-before-input -p ipv6-icmp --icmpv6-type echo-request -j DROP|' "$rules_v6"
        log "ICMP echo-request: DROP"
    fi
}

configure_ufw() {
    log "=== Настройка UFW ==="

    backup_file /etc/default/ufw

    # IPv6
    if grep -q '^IPV6=' /etc/default/ufw 2>/dev/null; then
        sed -i "s/^IPV6=.*/IPV6=${UFW_ENABLE_IPV6}/" /etc/default/ufw
    else
        echo "IPV6=${UFW_ENABLE_IPV6}" >> /etc/default/ufw
    fi

    # Политики по умолчанию
    ufw default "$UFW_DEFAULT_IN" incoming
    ufw default "$UFW_DEFAULT_OUT" outgoing

    # Loopback
    ufw allow in on lo
    ufw deny in from 127.0.0.0/8
    ufw deny in from ::1

    # SSH (идемпотентно)
    ufw status numbered | grep -qE "[[:space:]]${UFW_SSH_PORT}/tcp[[:space:]]" || \
        ufw allow "${UFW_SSH_PORT}/tcp" comment 'SSH (AutoSec)'

    # HTTP/HTTPS (идемпотентно)
    ufw status numbered | grep -qE "[[:space:]]${UFW_HTTP_PORT}/tcp[[:space:]]" || \
        ufw allow "${UFW_HTTP_PORT}/tcp" comment 'HTTP (AutoSec)'
    ufw status numbered | grep -qE "[[:space:]]${UFW_HTTPS_PORT}/tcp[[:space:]]" || \
        ufw allow "${UFW_HTTPS_PORT}/tcp" comment 'HTTPS (AutoSec)'

    # Дополнительные порты
    if [[ -n "$UFW_EXTRA_PORTS" ]]; then
        IFS=', ' read -ra PORTS <<< "$UFW_EXTRA_PORTS"
        for port in "${PORTS[@]}"; do
            [[ -z "$port" ]] && continue
            if [[ "$port" =~ ^[0-9]+(/tcp|/udp)?$ ]]; then
                ufw status numbered | grep -qE "[[:space:]]${port}[[:space:]]" || \
                    ufw allow "$port" comment 'extra (AutoSec)'
                log "  Доп. порт разрешён: $port"
            else
                log "[WARN] Пропущен некорректный порт: '$port'"
            fi
        done
    fi

    # ICMP
    configure_icmp

    # КРИТИЧНО: guard от самоблокировки
    if ! ufw status | grep -qE "[[:space:]]${UFW_SSH_PORT}/tcp[[:space:]]+ALLOW"; then
        err "SSH-порт ${UFW_SSH_PORT}/tcp не найден в правилах UFW!"
        err "Прерываю — включение UFW без SSH-порта заблокирует доступ."
        exit 1
    fi

    # Активация
    echo "y" | ufw enable
    ufw reload
    log "UFW активирован"
    ufw status verbose | tee -a "$LOG_FILE"
}

# =============================================================================
#  НАСТРОЙКА fail2ban
# =============================================================================

configure_fail2ban() {
    log "=== Настройка fail2ban ==="

    backup_file /etc/fail2ban/jail.local

    cat > /etc/fail2ban/jail.local <<EOF
# AutoSec — $(date)
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
        [[ "$F2B_SENDMAIL_ON_BAN" == "yes" ]] && \
            echo "action = %(action_mwl)s" >> /etc/fail2ban/jail.local
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

    systemctl enable --now fail2ban
    systemctl restart fail2ban

    # Ждём появления jail (до 10 сек)
    local i
    for i in {1..10}; do
        if fail2ban-client status sshd &>/dev/null; then break; fi
        sleep 1
    done

    if systemctl is-active --quiet fail2ban; then
        log "fail2ban активен"
        fail2ban-client status sshd 2>/dev/null | tee -a "$LOG_FILE" || \
            log "[WARN] jail 'sshd' ещё не зарегистрирован — проверьте позже"
    else
        log "[WARN] fail2ban не запустился, см. journalctl -u fail2ban"
    fi
}

# =============================================================================
#  ФИНАЛЬНАЯ ПРОВЕРКА
# =============================================================================

final_check() {
    log "=== Финальная проверка ==="
    local errors=0

    echo ""
    echo "============================================================================="
    echo "  AutoSec — финальный отчёт"
    echo "============================================================================="

    if ufw status | grep -q "Status: active"; then
        echo "  ✅ UFW:           активен"
    else
        echo "  ❌ UFW:           НЕ АКТИВЕН"
        errors=$((errors + 1))
    fi

    if systemctl is-active --quiet fail2ban; then
        echo "  ✅ fail2ban:      активен"
    else
        echo "  ❌ fail2ban:      НЕ ЗАПУЩЕН"
        errors=$((errors + 1))
    fi

    if ufw status | grep -qE "[[:space:]]${UFW_SSH_PORT}/tcp[[:space:]]+ALLOW"; then
        echo "  ✅ SSH port:      ${UFW_SSH_PORT}/tcp разрешён"
    else
        echo "  ❌ SSH port:      ${UFW_SSH_PORT}/tcp НЕ разрешён"
        errors=$((errors + 1))
    fi

    # Информативно: текущее состояние входа по паролю (не блокирующая проверка)
    if command -v sshd &>/dev/null; then
        local pw_auth root_login
        pw_auth=$(sshd -T 2>/dev/null | awk '/^passwordauthentication / {print $2}' || echo "?")
        root_login=$(sshd -T 2>/dev/null | awk '/^permitrootlogin / {print $2}' || echo "?")
        echo "  ℹ️  sshd:          PasswordAuthentication=$pw_auth, PermitRootLogin=$root_login"
    fi

    echo "============================================================================="
    echo ""
    if [[ $errors -eq 0 ]]; then
        echo "  🎉  Базовая защита установлена."
    else
        echo "  ⚠️  Обнаружено $errors проблем. Лог: $LOG_FILE"
    fi
    echo ""
    echo "  ВАЖНО — следующий шаг:"
    echo "  Сейчас вход по паролю всё ещё активен. Пока вы не перешли"
    echo "  на SSH-ключи, fail2ban — единственная преграда против brute-force."
    echo "  Как только настроите ключи:"
    echo "    1. Скопируйте свой публичный ключ: ssh-copy-id user@host"
    echo "    2. Проверьте вход по ключу В НОВОЙ СЕССИИ (не закрывая текущую!)"
    echo "    3. Отключите вход по паролю в /etc/ssh/sshd_config.d/:"
    echo "         PasswordAuthentication no"
    echo "         PermitRootLogin prohibit-password"
    echo "    4. sudo sshd -t && sudo systemctl reload ssh"
    echo ""
    echo "  Полезные команды:"
    echo "    sudo ufw status verbose"
    echo "    sudo fail2ban-client status sshd"
    echo "    sudo tail -f $LOG_FILE"
    echo ""

    [[ $errors -eq 0 ]] && return 0 || return 1
}

# =============================================================================
#  MAIN
# =============================================================================

main() {
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════════════╗"
    echo "  ║  AutoSec v0.2 — первичная защита (UFW + fail2ban)             ║"
    echo "  ║  Этап: ДО перехода на SSH-ключи (sshd не модифицируется)      ║"
    echo "  ╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    check_root
    detect_distro
    log "Дистрибутив: $DISTRO ${DISTRO_LIKE:+(like: $DISTRO_LIKE)}"

    autodetect_ssh_port
    validate_config

    system_upgrade
    install_packages
    configure_ufw
    configure_fail2ban
    final_check
}

main "$@"
