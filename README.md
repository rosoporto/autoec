# AutoSec

> Bash-скрипт первичной настройки защиты Linux-сервера: `ufw` + `fail2ban`. **Этап «до перехода на SSH-ключи»** — скрипт сознательно не трогает `sshd`, чтобы не сломать вход по паролю.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
![Shell](https://img.shields.io/badge/shell-bash-89e051)

---

## Назначение

AutoSec ставит **базовый периметр** на свежекупленный сервер, пока у вас ещё только доступ по паролю:

- закрывает всё лишнее на firewall,
- защищает SSH от brute-force через `fail2ban`,
- обновляет систему перед установкой.

**SSH hardening (отключение пароля, `PermitRootLogin`, ужесточение шифров, sysctl, AppArmor и т.п.) сюда не входит** — это следующий этап, после того как вы настроили вход по ключу и убедились, что он работает. См. [Следующий шаг](#следующий-шаг-переход-на-ssh-ключи).

---

## Требования

- ОС из списка [поддерживаемых дистрибутивов](#поддерживаемые-дистрибутивы)
- `bash` 4.0+
- `sudo` или root-доступ
- `wget` / `curl` для загрузки

---

## Быстрый старт

**Вариант 1 — wget:**

```bash
wget https://raw.githubusercontent.com/rosoporto/autosec/main/autosec.sh
chmod +x autosec.sh
nano autosec.sh        # (опционально) отредактировать настройки
sudo ./autosec.sh
```

**Вариант 2 — git clone:**

```bash
git clone https://github.com/rosoporto/autosec.git
cd autosec
chmod +x autosec.sh
sudo ./autosec.sh
```

В конце вы увидите:

```
🎉  Базовая защита установлена.

  ВАЖНО — следующий шаг:
  Сейчас вход по паролю всё ещё активен. Пока вы не перешли
  на SSH-ключи, fail2ban — единственная преграда против brute-force.
  ...
```

---

## Что делает скрипт

| Шаг | Действие |
| --- | --- |
| **Обновление системы** | `apt/dnf/pacman/apk upgrade` перед установкой (отключаемо: `DO_SYSTEM_UPGRADE="no"`) |
| **Установка пакетов** | `ufw`, `fail2ban` |
| **UFW** | Политики по умолчанию, loopback, открытие SSH/HTTP/HTTPS, доп. портов, ICMP, hard-guard от самоблокировки, активация |
| **fail2ban** | `jail.local` с конфигом для `sshd`, ожидание регистрации jail (до 10 с), вывод статуса |
| **Финальная проверка** | UFW активен, fail2ban работает, SSH-порт открыт. Дополнительно: вывод текущих `PasswordAuthentication` и `PermitRootLogin` (информативно) |

Скрипт **не модифицирует** `/etc/ssh/sshd_config` — это обязательное условие на этапе «до ключей».

### Гарантии безопасности

- Бэкапы изменяемых файлов: `before.rules`, `before6.rules`, `/etc/default/ufw`, `jail.local` — все с `.bak.<timestamp>`.
- Идемпотентность: повторный запуск не создаёт дубликатов правил UFW.
- **Hard-guard от самоблокировки**: перед `ufw enable` скрипт проверяет, что правило для SSH-порта реально присутствует в выводе `ufw status`. Если нет — выполнение прерывается, UFW не активируется.
- Автоопределение SSH-порта через `sshd -T` (если порт отличается от `UFW_SSH_PORT` в настройках — будет использован реальный).

---

## Поддерживаемые дистрибутивы

- **Debian** / **Ubuntu**
- **RHEL** / **CentOS** / **Rocky Linux** / **AlmaLinux**
- **Fedora**
- **Arch Linux** / **Manjaro**
- **Alpine Linux** ⚠️ — использует OpenRC вместо systemd; установите `F2B_BACKEND="auto"` перед запуском

---

## Настройка

Все параметры — в начале скрипта.

### Система

| Переменная | По умолчанию | Описание |
| --- | --- | --- |
| `DO_SYSTEM_UPGRADE` | `yes` | Выполнить `upgrade` пакетного менеджера перед установкой |
| `LOG_FILE` | `/var/log/autosec_install.log` | Путь к логу установки |

### UFW

| Переменная | По умолчанию | Описание |
| --- | --- | --- |
| `UFW_ENABLE_IPV6` | `yes` | Включить поддержку IPv6 |
| `UFW_DEFAULT_IN` | `deny` | Политика входящих по умолчанию (`deny` / `allow` / `reject`) |
| `UFW_DEFAULT_OUT` | `allow` | Политика исходящих по умолчанию |
| `UFW_SSH_PORT` | `22` | Порт SSH |
| `AUTODETECT_SSH_PORT` | `yes` | Прочитать реальный порт sshd через `sshd -T` и использовать его, если отличается от `UFW_SSH_PORT` |
| `UFW_HTTP_PORT` | `80` | Порт HTTP |
| `UFW_HTTPS_PORT` | `443` | Порт HTTPS |
| `UFW_EXTRA_PORTS` | `""` | Доп. порты через запятую, например `"8080,9090/udp"` |
| `UFW_ALLOW_PING` | `yes` | Разрешить ICMP echo-request (`no` — реально DROP-ает echo-request в IPv4 и IPv6) |

### fail2ban

| Переменная | По умолчанию | Описание |
| --- | --- | --- |
| `F2B_SSH_MAXRETRY` | `3` | Число неудачных попыток входа перед баном |
| `F2B_SSH_FINDTIME` | `600` | Окно подсчёта попыток (сек) |
| `F2B_SSH_BANTIME` | `3600` | Длительность бана (сек) |
| `F2B_SSH_ENABLED` | `true` | Включить защиту SSH |
| `F2B_BACKEND` | `systemd` | Бэкенд логирования (`systemd` или `auto`; для Alpine — `auto`) |
| `F2B_BANACTION` | `iptables-multiport` | Действие при бане |
| `F2B_SENDMAIL` | `""` | Email для уведомлений (пусто = отключено) |
| `F2B_SENDMAIL_ON_BAN` | `no` | Отправлять письмо при каждом бане |

### Пример кастомной конфигурации

```bash
# SSH на нестандартном порту + порты приложения
UFW_SSH_PORT="2222"
UFW_EXTRA_PORTS="3000,8080,5353/udp"

# Строгий fail2ban: 2 попытки → бан на сутки
F2B_SSH_MAXRETRY="2"
F2B_SSH_BANTIME="86400"

# На слабом VPS отключить обновление системы при первом запуске
DO_SYSTEM_UPGRADE="no"
```

---

## Следующий шаг: переход на SSH-ключи

AutoSec умышленно оставляет вход по паролю включённым. После установки:

1. **Сгенерируйте ключ на локальной машине** (если ещё нет):
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```
2. **Скопируйте публичный ключ на сервер**:
   ```bash
   ssh-copy-id user@server
   ```
3. **Проверьте вход по ключу В НОВОЙ сессии**, **не закрывая текущую**:
   ```bash
   ssh user@server
   ```
4. **Только после успешной проверки** отключите пароль. Создайте `/etc/ssh/sshd_config.d/10-autosec.conf`:
   ```
   PasswordAuthentication no
   PermitRootLogin prohibit-password
   KbdInteractiveAuthentication no
   ```
5. Проверьте и перезагрузите:
   ```bash
   sudo sshd -t && sudo systemctl reload ssh
   ```

> Не выходите из исходной SSH-сессии, пока не убедились, что ключ работает и пароль отключён корректно. Если что-то пошло не так — у вас всё ещё открыта рабочая сессия для отката.

---

## Проверка после установки

```bash
sudo ufw status verbose
sudo systemctl status fail2ban
sudo fail2ban-client status sshd
cat /var/log/autosec_install.log
```

---

## Типичные проблемы

### Скрипт требует root

```bash
sudo ./autosec.sh
```

### UFW не найден в репозитории (CentOS/RHEL)

В некоторых конфигурациях `ufw` отсутствует в стандартных репозиториях. Подключите EPEL и повторите запуск:

```bash
sudo dnf install epel-release
sudo ./autosec.sh
```

### Скрипт прервался с «SSH-порт … не найден в правилах UFW»

Это сработал hard-guard. UFW **не активирован**, доступ не потерян. Проверьте, что `UFW_SSH_PORT` соответствует реальному порту `sshd`:

```bash
sudo sshd -T | grep '^port '
```

Если порт отличается — либо включите `AUTODETECT_SSH_PORT="yes"`, либо поставьте правильное значение в `UFW_SSH_PORT` и перезапустите скрипт.

### fail2ban заблокировал мой IP

Разблокировать конкретный IP в jail `sshd`:

```bash
sudo fail2ban-client set sshd unbanip <IP>
```

### Alpine Linux: fail2ban не запускается

Alpine использует OpenRC, а не systemd. Перед запуском установите:

```bash
F2B_BACKEND="auto"
```

### Откат изменений UFW/fail2ban

Все изменённые конфиги бэкапятся с суффиксом `.bak.<unix_timestamp>`. Найти их:

```bash
ls -la /etc/ufw/*.bak.* /etc/fail2ban/*.bak.* /etc/default/ufw.bak.* 2>/dev/null
```

Откатить вручную, заменив текущие файлы соответствующими `.bak.*`, и перезагрузить сервисы:

```bash
sudo ufw reload
sudo systemctl restart fail2ban
```

---

## Лицензия

MIT © 2026
