#!/bin/bash

# Скрипт для автоматической установки Pterodactyl Panel на Ubuntu 20.04/22.04 с автонастройкой nginx и SSL

set -e

# === НАСТРОЙКИ ===
PANEL_DOMAIN="148.253.209.153" # <-- Замените на ваш домен!
EMAIL="egord2799@gmail.com"         # <-- Замените на ваш email для Let's Encrypt!

# === ОБНОВЛЕНИЕ СИСТЕМЫ ===
echo "Обновление системы..."
sudo apt update && sudo apt upgrade -y

# === УСТАНОВКА ЗАВИСИМОСТЕЙ ===
echo "Установка зависимостей..."
sudo apt install -y nginx mysql-server redis-server git curl zip unzip tar \
    php8.1 php8.1-cli php8.1-fpm php8.1-gd php8.1-mysql php8.1-pgsql php8.1-redis \
    php8.1-mbstring php8.1-xml php8.1-curl php8.1-zip php8.1-bcmath php8.1-gmp \
    php8.1-imagick php8.1-intl php8.1-common php8.1-ldap php8.1-xmlrpc php8.1-soap \
    composer certbot python3-certbot-nginx

# === СОЗДАНИЕ БАЗЫ ДАННЫХ ===
echo "Создание базы данных..."
DB_PASS=$(openssl rand -base64 16)
sudo mysql -e "CREATE DATABASE panel;"
sudo mysql -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY '$DB_PASS';"
sudo mysql -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1';"
sudo mysql -e "FLUSH PRIVILEGES;"

# === СКАЧИВАНИЕ ПАНЕЛИ ===
echo "Скачивание панели Pterodactyl..."
cd /var/www/
sudo mkdir -p pterodactyl
sudo chown $USER:$USER pterodactyl
cd pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
rm panel.tar.gz

# === УСТАНОВКА PHP ЗАВИСИМОСТЕЙ ===
echo "Установка зависимостей PHP (composer)..."
composer install --no-dev --optimize-autoloader

# === НАСТРОЙКА .env ===
echo "Копирование .env файла..."
cp .env.example .env

php artisan key:generate --force

sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env

# === МИГРАЦИЯ БД ===
echo "Миграция базы данных и установка..."
php artisan migrate --seed --force

# === ПРАВА ДОСТУПА ===
echo "Настройка прав доступа..."
sudo chown -R www-data:www-data /var/www/pterodactyl/*
sudo chmod -R 755 /var/www/pterodactyl/storage /var/www/pterodactyl/bootstrap/cache

# === НАСТРОЙКА NGINX ===
echo "Настройка nginx..."
NGINX_CONF="/etc/nginx/sites-available/pterodactyl"
sudo bash -c "cat > $NGINX_CONF" <<EOL
server {
    listen 80;
    server_name $PANEL_DOMAIN;
    root /var/www/pterodactyl/public;

    index index.php;
    charset utf-8;
    client_max_body_size 100m;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.(php)
    {
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param HTTP_PROXY "";
        fastcgi_intercept_errors on;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires max;
        log_not_found off;
    }
}
EOL

sudo ln -sf $NGINX_CONF /etc/nginx/sites-enabled/pterodactyl
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# === SSL через Let's Encrypt ===
echo "Настройка SSL через Let's Encrypt..."
sudo certbot --nginx -d $PANEL_DOMAIN --non-interactive --agree-tos -m $EMAIL --redirect

# === ФИНАЛ ===
echo "\nУстановка завершена!"
echo "Данные для базы данных:"
echo "  Пользователь: pterodactyl"
echo "  Пароль: $DB_PASS"
echo "  База: panel"
echo "Панель доступна по адресу: https://$PANEL_DOMAIN"
echo "Откройте .env и настройте остальные параметры (почта, домен и т.д.)"
echo "Если домен не настроен, настройте A-запись на ваш сервер!" 