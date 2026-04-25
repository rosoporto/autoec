# AutoSec

> Bash-скрипт автоматической установки и настройки `ufw` + `fail2ban` на свежий сервер.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

---

## Быстрый старт

```bash
# 1. Скачать скрипт
wget https://raw.githubusercontent.com/rosoporto/autoec/main/autosec.sh

# 2. (Опционально) Отредактировать настройки
nano autosec.sh

# 3. Запустить
chmod +x autosec.sh
sudo ./autosec.sh
```

В конце вы получите сообщение:

```
🎉  Congratulations! Сервер защищён.
```

---

## Что делает скрипт

| Компонент | Действие |
|-----------|----------|
| **UFW** | Устанавливает, настраивает политики по умолчанию, открывает нужные порты, активирует фаервол |
| **fail2ban** | Устанавливает, создаёт `jail.local`, защищает SSH от брутфорса, запускает сервис |
| **Проверка** | Проверяет, что всё работает, и выводит финальный отчёт |

---

## Поддерживаемые дистрибутивы

- **Debian** / **Ubuntu**
- **RHEL** / **CentOS** / **Rocky Linux** / **AlmaLinux**
- **Fedora**
- **Arch Linux** / **Manjaro**
- **Alpine Linux**

---

## Настройка

Все параметры находятся в начале скрипта. Измените их перед запуском.

### UFW

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `UFW_ENABLE_IPV6` | `yes` | Включить поддержку IPv6 |
| `UFW_DEFAULT_IN` | `deny` | Политика входящих по умолчанию (`deny` / `allow` / `reject`) |
| `UFW_DEFAULT_OUT` | `allow` | Политика исходящих по умолчанию |
| `UFW_SSH_PORT` | `22` | Порт SSH |
| `UFW_HTTP_PORT` | `80` | Порт HTTP |
| `UFW_HTTPS_PORT` | `443` | Порт HTTPS |
| `UFW_EXTRA_PORTS` | `""` | Дополнительные порты через запятую, например `"8080,9090"` |
| `UFW_ALLOW_PING` | `yes` | Разрешить ICMP echo-request (ping) |

### fail2ban

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `F2B_SSH_MAXRETRY` | `3` | Число неудачных попыток входа перед баном |
| `F2B_SSH_FINDTIME` | `600` | Окно времени для подсчёта попыток (секунды) |
| `F2B_SSH_BANTIME` | `3600` | Длительность бана (секунды) |
| `F2B_SSH_ENABLED` | `true` | Включить защиту SSH |
| `F2B_BACKEND` | `systemd` | Бэкенд логирования (`systemd` или `auto`) |
| `F2B_BANACTION` | `iptables-multiport` | Действие при бане |
| `F2B_SENDMAIL` | `""` | Email для уведомлений (пусто = отключено) |
| `F2B_SENDMAIL_ON_BAN` | `no` | Отправлять письмо при каждом бане |

### Пример кастомной конфигурации

```bash
# Открываем SSH на нестандартном порту + доп. порт для приложения
UFW_SSH_PORT="2222"
UFW_EXTRA_PORTS="3000,8080"

# Строгий fail2ban: бан на сутки после 2 попыток
F2B_SSH_MAXRETRY="2"
F2B_SSH_BANTIME="86400"
```

---

## Проверка после установки

```bash
# Статус фаервола
sudo ufw status verbose

# Статус fail2ban
sudo systemctl status fail2ban
sudo fail2ban-client status sshd

# Лог установки
cat /var/log/autosec_install.log
```

---

## Типичные проблемы

### Скрипт требует root
```bash
sudo ./autosec.sh
```

### UFW не найден в репозитории (CentOS/RHEL)
В редких случаях `ufw` отсутствует в репозитории. Установите EPEL:
```bash
sudo dnf install epel-release
sudo ./autosec.sh
```

### Потеря SSH-доступа
Скрипт **всегда** открывает порт SSH (`UFW_SSH_PORT`) перед активацией UFW. Если вы меняли порт SSH вручную после установки ОС — убедитесь, что `UFW_SSH_PORT` совпадает с фактическим портом в `/etc/ssh/sshd_config`.

---

## Лицензия

MIT © 2026
