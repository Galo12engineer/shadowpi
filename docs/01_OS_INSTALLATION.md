# 01. Установка ОС

## Выбор ОС

### Вариант 1: Raspberry Pi OS Lite 64-bit (рекомендуется для начинающих)
- ✅ Официальная, стабильная
- ✅ Хорошая поддержка оборудования
- ⚠️ Немного тяжеловата

### Вариант 2: DietPi (рекомендуется для производительности)
- ✅ Очень легкая (~400MB RAM idle)
- ✅ Быстрая
- ✅ Оптимизирована для headless
- ⚠️ Немного меньше документации

### Вариант 3: Ubuntu Server 64-bit
- ✅ Актуальные пакеты
- ⚠️ Потребляет больше ресурсов

## Шаг 1: Скачивание и запись ОС

### Raspberry Pi OS

```bash
# На вашем компьютере (Mac):

# 1. Установите Raspberry Pi Imager
brew install --cask raspberry-pi-imager

# 2. Запустите Imager
open /Applications/Raspberry\ Pi\ Imager.app

# Или скачайте с https://www.raspberrypi.com/software/
```

**В Imager:**
1. Выберите устройство: Raspberry Pi 4
2. ОС: Raspberry Pi OS Lite (64-bit)
3. Хранилище: Ваша SD карта (минимум 8GB, рекомендуется 16GB+)
4. **Нажмите шестеренку** ⚙️ для дополнительных настроек:

```
Имя устройства: anonrouter
Включить SSH: ✓ (использовать пароль)
Имя пользователя: admin
Пароль: [ваш_пароль]
Настроить WiFi: ✓ (если нужен для первой настройки)
  SSID: Ваша_WiFi_сеть
  Пароль: [пароль_WiFi]
  Страна: RU
Установить локаль:
  Часовой пояс: Europe/Moscow
  Раскладка: ru
```

5. Нажмите "Сохранить"
6. Нажмите "Записать" и подтвердите

### DietPi (альтернатива)

```bash
# Скачайте образ
curl -LO https://dietpi.com/downloads/images/DietPi_RPi-ARMv8-Bookworm.7z

# Распакуйте
7z x DietPi_RPi-ARMv8-Bookworm.7z

# Запишите на SD карту (замените /dev/diskX на вашу SD карту!)
# Узнайте диск: diskutil list
sudo dd if=DietPi_RPi-ARMv8-Bookworm.img of=/dev/rdiskX bs=4m status=progress
```

## Шаг 2: Первый запуск

```bash
# Вставьте SD карту в Raspberry Pi
# Подключите питание (минимум 3A)
# Подождите ~2 минуты для загрузки

# Найдите IP адрес Pi:
# 1. Через роутер (192.168.1.X обычно)
# 2. Или используйте:
ping anonrouter.local
# или для DietPi:
ping DietPi.local

# SSH подключение
ssh admin@anonrouter.local
# Пароль: тот что задали в Imager
```

## Шаг 3: Базовая настройка

```bash
# После входа по SSH:

# 1. Обновление системы
sudo apt update && sudo apt upgrade -y

# 2. Raspberry Pi configuration (только для Pi OS)
sudo raspi-config

# В меню:
# - System Options → S4 Hostname → anonrouter
# - Interface Options → I2 SSH → Enable (должен быть уже)
# - Localisation → L1 Locale → en_US.UTF-8 и ru_RU.UTF-8
# - Localisation → L2 Timezone → Europe/Moscow
# - Advanced → A1 Expand Filesystem (важно!)
# - Performance → P2 GPU Memory → 16 (минимум, нам GUI не нужна)
# Finish → Reboot

# 3. После перезагрузки, переподключиться:
ssh admin@anonrouter.local

# 4. Установить базовые инструменты
sudo apt install -y \
  vim \
  htop \
  curl \
  wget \
  git \
  screen \
  net-tools \
  iptables \
  nftables \
  ufw

# 5. Отключить IPv6 (против утечек)
echo "net.ipv6.conf.all.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
echo "net.ipv6.conf.lo.disable_ipv6 = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 6. Включить IP forwarding
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Проверка
sysctl net.ipv4.ip_forward  # должно быть = 1
sysctl net.ipv6.conf.all.disable_ipv6  # должно быть = 1
```

## Шаг 4: Настройка SSH (рекомендуется)

```bash
# НА ВАШЕМ КОМПЬЮТЕРЕ (Mac), создайте SSH ключ если нет:
ssh-keygen -t ed25519 -C "pi-router"
# Нажмите Enter для сохранения в ~/.ssh/id_ed25519

# Скопируйте ключ на Pi:
ssh-copy-id admin@anonrouter.local

# Теперь можно подключаться без пароля:
ssh admin@anonrouter.local

# НА PI: Отключите вход по паролю (опционально, для безопасности)
sudo nano /etc/ssh/sshd_config

# Измените:
PasswordAuthentication no
PubkeyAuthentication yes

# Сохраните (Ctrl+O, Enter, Ctrl+X) и перезапустите SSH:
sudo systemctl restart ssh
```

## Шаг 5: Проверка железа

```bash
# Проверьте что Pi видит вашу WiFi адаптер:
iwconfig
# Должно показать wlan0

# Проверьте Ethernet:
ip addr show eth0

# Проверьте температуру (должна быть <60°C в idle):
vcgencmd measure_temp

# Проверьте память:
free -h

# Проверьте место на диске:
df -h
```

## ✅ Готово!

ОС установлена и настроена. Переходите к **02_BASE_PACKAGES.md**
