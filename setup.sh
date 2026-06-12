#!/bin/bash
# setup.sh for ANNOBON NODE
set -e
[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

echo "Modo de Sync: [1] semanal, [2] manual, [3] satelite"
read -p "Seleccionar [1-3]: " S_MODE
case "$S_MODE" in 1) M="weekly";; 3) M="satellite";; *) M="manual";; esac
read -p "Enter Master Sync Token: " SYNC_TOK

echo "🚀 Installing ANNOBON SPECIAL NODE ($M)..."
apt update && apt install -y python3.12 python3.12-venv mysql-server nginx git openssl
id bioko &>/dev/null || useradd -r -s /usr/sbin/nologin -d /opt/bioko-health bioko
DB_PASS=$(openssl rand -hex 12)
mysql -e "CREATE DATABASE IF NOT EXISTS bioko_health; CREATE USER IF NOT EXISTS 'bioko_user'@'localhost' IDENTIFIED BY '$DB_PASS'; GRANT ALL PRIVILEGES ON bioko_health.* TO 'bioko_user'@'localhost'; FLUSH PRIVILEGES;"

python3.12 -m venv venv && ./venv/bin/pip install -r requirements.txt

# Config (Annobón Specific)
cp env-templates/annobon.env.template .env
SEC_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))")
sed -i "s|SECRET_KEY=.*|SECRET_KEY=$SEC_KEY|" .env
sed -i "s|SYNC_API_TOKEN=.*|SYNC_API_TOKEN=$SYNC_TOK|" .env
sed -i "s|ANNOBON_SYNC_MODE=.*|ANNOBON_SYNC_MODE=$M|" .env
sed -i "s|bioko_user:.*@localhost|bioko_user:$DB_PASS@localhost|g" .env

./venv/bin/python scripts/seed_db.py

# Services
mkdir -p /etc/ssl/bioko
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/bioko/privkey.pem -out /etc/ssl/bioko/fullchain.pem -subj "/C=GQ/CN=annobon.salud.local"
cp deploy/nginx-bioko.conf /etc/nginx/sites-available/bioko-health
ln -sf /etc/nginx/sites-available/bioko-health /etc/nginx/sites-enabled/
cp deploy/bioko-health.service /etc/systemd/system/
systemctl daemon-reload && systemctl enable mysql nginx bioko-health
systemctl restart mysql nginx bioko-health
echo "✅ ANNOBON SETUP COMPLETE"
