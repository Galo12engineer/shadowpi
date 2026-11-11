# 09. Веб-панель управления

## 🌐 Обзор веб-панели

Веб-панель предоставляет удобный интерфейс для управления роутером:
- ✅ Статус всех сервисов в реальном времени
- ✅ Управление (старт/стоп/перезапуск)
- ✅ Проверка IP и местоположения
- ✅ Мониторинг системы (CPU, RAM, температура)
- ✅ Логи
- ✅ Быстрые действия

**Доступ**: http://anonrouter.local:8080 (или http://IP_адрес:8080)

## 📦 Установка (уже сделано в master-install.sh)

Если вы запускали `master-install.sh`, всё уже установлено. Если нет:

```bash
# Установка Nginx
sudo apt install -y nginx

# Установка PHP
sudo apt install -y php-fpm php-cli php-common

# Запуск
sudo systemctl enable nginx php*-fpm
sudo systemctl start nginx php*-fpm
```

## 🔧 Настройка Nginx

### Конфигурация виртуального хоста

```bash
sudo nano /etc/nginx/sites-available/anonrouter
```

```nginx
server {
    listen 8080;
    listen [::]:8080;
    
    server_name _;
    
    root /var/www/anonrouter;
    index index.php index.html;
    
    # Basic Authentication
    
    # Логи
    access_log /var/log/nginx/anonrouter-access.log;
    error_log /var/log/nginx/anonrouter-error.log;
    
    # PHP обработка
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }
    
    # Статические файлы
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Запретить доступ к скрытым файлам
    location ~ /\.ht {
        deny all;
    }
    
    # Кеширование статики
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
```

```bash
# Активировать конфиг
sudo ln -sf /etc/nginx/sites-available/anonrouter /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Тест конфигурации
sudo nginx -t

# Перезапуск
sudo systemctl restart nginx
```

## 🔐 Настройка аутентификации

### Создание пароля для веб-панели

```bash
# NOTE: nginx basic auth is no longer used (it had no lockout and shared the panel password).
# The htpasswd steps below are obsolete; the panel login in config.php is the only gate.
# Создайте папку для htpasswd
sudo mkdir -p /etc/nginx/auth

# Сгенерируйте пароль
# Замените "admin" и "YourPassword" на свои
echo "admin:$(openssl passwd -apr1 YourPassword)" | sudo tee /etc/nginx/auth/htpasswd

# Установите права
sudo chmod 640 /etc/nginx/auth/htpasswd
sudo chown www-data:www-data /etc/nginx/auth/htpasswd

# Проверка
cat /etc/nginx/auth/htpasswd
```

### Изменение пароля

```bash
# Новый пароль
echo "admin:$(openssl passwd -apr1 NewPassword)" | sudo tee /etc/nginx/auth/htpasswd

# Перезапуск Nginx
sudo systemctl restart nginx
```

## 📂 Развертывание файлов веб-панели

### Копирование файлов из проекта

```bash
# Создайте директорию
sudo mkdir -p /var/www/anonrouter

# Скопируйте файлы из проекта
sudo cp ~/shadowpi/web-ui/* /var/www/anonrouter/

# Установите права
sudo chown -R www-data:www-data /var/www/anonrouter
sudo chmod -R 755 /var/www/anonrouter

# Для PHP API нужны дополнительные права
sudo chmod +x /var/www/anonrouter/api.php
```

## 🔧 Настройка sudo для PHP

PHP скрипт (`api.php`) должен иметь возможность управлять сервисами через `sudo` без пароля:

```bash
# Создайте sudoers файл для www-data
sudo visudo -f /etc/sudoers.d/anonrouter
```

Добавьте:

```sudoers
# Allow www-data to control services without password
www-data ALL=(ALL) NOPASSWD: /bin/systemctl start openvpn-windscribe
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop openvpn-windscribe
www-data ALL=(ALL) NOPASSWD: /bin/systemctl restart openvpn-windscribe
www-data ALL=(ALL) NOPASSWD: /bin/systemctl status openvpn-windscribe
www-data ALL=(ALL) NOPASSWD: /bin/systemctl is-active openvpn-windscribe

www-data ALL=(ALL) NOPASSWD: /bin/systemctl start v2raya
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop v2raya
www-data ALL=(ALL) NOPASSWD: /bin/systemctl restart v2raya
www-data ALL=(ALL) NOPASSWD: /bin/systemctl is-active v2raya

www-data ALL=(ALL) NOPASSWD: /bin/systemctl start tor
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop tor
www-data ALL=(ALL) NOPASSWD: /bin/systemctl is-active tor

www-data ALL=(ALL) NOPASSWD: /bin/systemctl start hostapd
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop hostapd
www-data ALL=(ALL) NOPASSWD: /bin/systemctl is-active hostapd

www-data ALL=(ALL) NOPASSWD: /bin/systemctl start dnsmasq
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop dnsmasq
www-data ALL=(ALL) NOPASSWD: /bin/systemctl is-active dnsmasq

www-data ALL=(ALL) NOPASSWD: /opt/shadowpi/scripts/start-all.sh
www-data ALL=(ALL) NOPASSWD: /opt/shadowpi/scripts/stop-all.sh
www-data ALL=(ALL) NOPASSWD: /opt/shadowpi/scripts/restart-all.sh
www-data ALL=(ALL) NOPASSWD: /opt/shadowpi/scripts/test-all.sh
www-data ALL=(ALL) NOPASSWD: /opt/shadowpi/scripts/toggle-tor.sh

www-data ALL=(ALL) NOPASSWD: /usr/sbin/iw dev wlan0 station dump
www-data ALL=(ALL) NOPASSWD: /usr/bin/vcgencmd measure_temp
```

```bash
# Проверка синтаксиса
sudo visudo -c

# Установите права
sudo chmod 440 /etc/sudoers.d/anonrouter
```

## 🧪 Тестирование веб-панели

### Проверка доступа

```bash
# Узнайте IP адрес Pi
hostname -I

# На вашем компьютере откройте браузер:
# http://192.168.1.X:8080
# ИЛИ
# http://anonrouter.local:8080

# Введите логин/пароль:
# Логин: admin
# Пароль: [тот что задали]
```

### Проверка API

```bash
# На Pi проверьте API работает
curl -s http://localhost:8080/api.php?action=vpn_status | jq

# Должен вернуть JSON:
# {"active":true,"ip":"xxx.xxx.xxx.xxx","server":"..."}
```

### Проверка PHP

```bash
# Создайте тестовый файл
echo "<?php phpinfo(); ?>" | sudo tee /var/www/anonrouter/test.php

# Откройте в браузере:
# http://anonrouter.local:8080/test.php

# Должна показаться страница PHP Info

# Удалите тестовый файл
sudo rm /var/www/anonrouter/test.php
```

## 🎨 Кастомизация интерфейса

### Изменение цветовой схемы

Отредактируйте `style.css`:

```bash
sudo nano /var/www/anonrouter/style.css
```

```css
:root {
    /* Измените эти цвета */
    --bg-primary: #0a0e27;        /* Основной фон */
    --bg-secondary: #141b3a;      /* Вторичный фон */
    --bg-card: #1a2245;           /* Фон карточек */
    --accent: #667eea;            /* Акцентный цвет */
    --accent-light: #764ba2;      /* Светлый акцент */
    --success: #48bb78;           /* Зеленый (успех) */
    --warning: #ed8936;           /* Оранжевый (предупреждение) */
    --danger: #f56565;            /* Красный (опасность) */
}
```

### Добавление логотипа

```bash
# Загрузите ваш логотип
sudo cp ~/mylogo.png /var/www/anonrouter/logo.png

# Измените header в index.html
sudo nano /var/www/anonrouter/index.html
```

```html
<header>
    <div class="logo">
        <img src="logo.png" width="40" height="40" alt="Logo">
        <h1>My Custom Router</h1>
    </div>
    ...
</header>
```

## 📊 Добавление новых фич в API

### Пример: добавить статус температуры

Отредактируйте `api.php`:

```bash
sudo nano /var/www/anonrouter/api.php
```

Добавьте новый case:

```php
case 'temperature':
    $temp = shell_exec('vcgencmd measure_temp');
    preg_match('/temp=([\d.]+)/', $temp, $matches);
    echo json_encode([
        'temperature' => floatval($matches[1] ?? 0)
    ]);
    break;
```

Используйте в JavaScript (`app.js`):

```javascript
async function updateTemperature() {
    const response = await fetch('api.php?action=temperature');
    const data = await response.json();
    document.getElementById('temp').textContent = data.temperature + '°C';
}
```

## 🔒 HTTPS (опционально)

### Самоподписанный сертификат

```bash
# Создайте SSL сертификат
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/anonrouter.key \
    -out /etc/nginx/ssl/anonrouter.crt \
    -subj "/CN=anonrouter.local"

# Измените Nginx конфиг
sudo nano /etc/nginx/sites-available/anonrouter
```

```nginx
server {
    listen 8443 ssl;
    listen [::]:8443 ssl;
    
    ssl_certificate /etc/nginx/ssl/anonrouter.crt;
    ssl_certificate_key /etc/nginx/ssl/anonrouter.key;
    
    # ... остальное как раньше ...
}

# Redirect HTTP → HTTPS
server {
    listen 8080;
    return 301 https://$host:8443$request_uri;
}
```

```bash
sudo systemctl restart nginx

# Теперь открывайте: https://anonrouter.local:8443
# (игнорируйте предупреждение о сертификате)
```

## 🐛 Troubleshooting

### Не открывается веб-панель

```bash
# Проверьте Nginx работает
sudo systemctl status nginx

# Проверьте порт 8080 слушается
sudo netstat -tlnp | grep 8080

# Проверьте firewall не блокирует
sudo nft list ruleset | grep 8080

# Логи Nginx
sudo tail -f /var/log/nginx/error.log
```

### 502 Bad Gateway

```bash
# PHP-FPM не работает
sudo systemctl status php*-fpm

# Перезапустите
sudo systemctl restart php*-fpm nginx
```

### API не работает

```bash
# Проверьте права на файлы
ls -la /var/www/anonrouter/

# Проверьте sudo работает
sudo -u www-data sudo systemctl is-active openvpn-windscribe

# Проверьте PHP логи
sudo tail -f /var/log/php*-fpm.log
```

## ✅ Готово!

Веб-панель настроена и работает!

**Доступ**: http://anonrouter.local:8080  
**Логин**: admin  
**Пароль**: [ваш пароль]

Теперь вы можете управлять роутером через красивый веб-интерфейс! 🎉
