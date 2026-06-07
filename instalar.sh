#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  BIOKO HEALTH — Nodo de Annobón                                 ║
# ║                                                                  ║
# ║  ⚠️  REQUIERE APROBACIÓN MINISTERIAL                             ║
# ║                                                                  ║
# ║  Annobón opera de forma COMPLETAMENTE AISLADA de la red         ║
# ║  principal. La conectividad con el servidor central del          ║
# ║  Ministerio depende de la infraestructura disponible:           ║
# ║                                                                  ║
# ║  OPCIONES (definir con el Ministerio):                          ║
# ║    1. Sync semanal vía internet satelital                        ║
# ║    2. Sync manual cuando llega el barco/avión con USB            ║
# ║    3. Conexión satelital continua (coste adicional)             ║
# ║                                                                  ║
# ║  Mientras no se defina la conectividad, este nodo opera         ║
# ║  como sistema autónomo completo para la isla de Annobón.        ║
# ║                                                                  ║
# ║  Uso: sudo bash instalar.sh                                      ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

VERDE='\033[0;32m'; AMARILLO='\033[1;33m'; ROJO='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${VERDE}✓ $1${NC}"; }
info() { echo -e "${AMARILLO}→ $1${NC}"; }
warn() { echo -e "${AMARILLO}⚠  $1${NC}"; }
err()  { echo -e "${ROJO}✗ $1${NC}"; exit 1; }

[[ $EUID -ne 0 ]] && err "Ejecutar como root."
[[ ! -f "run.py" ]] && err "Ejecutar desde el directorio raíz."

APP_DIR="/opt/bioko_health"
SERVICE_USER="bioko"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║  BIOKO HEALTH — Nodo Annobón                            ║"
echo "║  Sistema Autónomo — San Antonio de Palé                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
warn "Este nodo opera de forma autónoma hasta que el Ministerio"
warn "defina la infraestructura de conectividad de Annobón."
echo ""

echo "  Modo de sincronización con el Ministerio:"
echo "    [1] Semanal — sync automático cuando haya internet"
echo "    [2] Manual — el operador activa el sync manualmente"
echo "    [3] Sin sync — completamente aislado (solo local)"
echo ""
read -p "  Seleccionar modo [1-3]: " SYNC_MODE
case "$SYNC_MODE" in
  1) ANNOBON_SYNC="weekly";;
  2) ANNOBON_SYNC="manual";;
  3) ANNOBON_SYNC="none";;
  *) ANNOBON_SYNC="manual";;
esac

# ── Interfaces ────────────────────────────────────────────────
INTERFACES=($(ip -o link show | awk -F': ' '{print $2}' | grep -v lo))
for i in "${!INTERFACES[@]}"; do
    IP_IF=$(ip -4 addr show "${INTERFACES[$i]}" 2>/dev/null | grep -oP '(?<=inet )\S+' | cut -d/ -f1 || echo "sin IP")
    printf "    [%d] %-12s  %s\n" "$i" "${INTERFACES[$i]}" "$IP_IF"
done
echo ""
read -p "  Interfaz LAN (tablets del personal sanitario): " LAN_IDX
LAN_IFACE="${INTERFACES[$LAN_IDX]}"
read -p "  IP estática del servidor [192.168.100.10]: " LAN_IP
LAN_IP="${LAN_IP:-192.168.100.10}"
SUBNET=$(echo "$LAN_IP" | cut -d. -f1-3)

# ── Dependencias ───────────────────────────────────────────────
info "Instalando dependencias..."
apt-get update -qq
apt-get install -y -qq \
    python3 python3-pip python3-venv nginx mysql-server \
    libmysqlclient-dev pkg-config build-essential \
    dnsmasq ufw curl net-tools
ok "Dependencias instaladas."

# ── IP estática ────────────────────────────────────────────────
info "Configurando IP estática $LAN_IP en $LAN_IFACE..."
cat > /etc/netplan/99-bioko-annobon.yaml << NETPLAN
network:
  version: 2
  ethernets:
    ${LAN_IFACE}:
      dhcp4: false
      addresses: [${LAN_IP}/24]
      nameservers:
        addresses: [${LAN_IP}]
NETPLAN
chmod 600 /etc/netplan/99-bioko-annobon.yaml
netplan apply 2>/dev/null || true

# ── DHCP para tablets ──────────────────────────────────────────
cat > /etc/dnsmasq.d/bioko-annobon.conf << DNSMASQ
interface=${LAN_IFACE}
bind-interfaces
dhcp-range=${SUBNET}.50,${SUBNET}.200,24h
dhcp-option=option:router,${LAN_IP}
dhcp-option=option:dns-server,${LAN_IP}
address=/salud.local/${LAN_IP}
DNSMASQ
systemctl stop systemd-resolved 2>/dev/null || true
systemctl disable systemd-resolved 2>/dev/null || true
systemctl enable dnsmasq && systemctl restart dnsmasq

# ── Firewall ───────────────────────────────────────────────────
ufw --force reset > /dev/null 2>&1
ufw default deny incoming && ufw default allow outgoing
ufw allow in on "$LAN_IFACE" to any port 22
ufw allow in on "$LAN_IFACE" to any port 80
ufw allow in on "$LAN_IFACE" to any port 53
ufw allow in on "$LAN_IFACE" to any port 67
echo 0 > /proc/sys/net/ipv4/ip_forward
echo "net.ipv4.ip_forward = 0" > /etc/sysctl.d/99-bioko-noforward.conf
ufw --force enable > /dev/null 2>&1
ok "Firewall configurado."

# ── Instalación principal ──────────────────────────────────────
if ! id "$SERVICE_USER" &>/dev/null; then
    useradd --system --shell /bin/bash --home-dir "$APP_DIR" --create-home "$SERVICE_USER"
fi
cp -r --no-preserve=ownership . "$APP_DIR/" 2>/dev/null || true
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --quiet --upgrade pip wheel
"$APP_DIR/venv/bin/pip" install --quiet -r "$APP_DIR/requirements.txt"

if [[ ! -f "$APP_DIR/.env" ]]; then
    cp "$APP_DIR/deploy/annobon/env.template" "$APP_DIR/.env"
    SECRET=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    sed -i "s|GENERAR-python3.*|$SECRET|" "$APP_DIR/.env"
    sed -i "s|LAN_HOST=.*|LAN_HOST=$LAN_IP|" "$APP_DIR/.env"
    sed -i "s|LAN_URL=.*|LAN_URL=http://$LAN_IP|" "$APP_DIR/.env"
    sed -i "s|ANNOBON_SYNC_MODE=.*|ANNOBON_SYNC_MODE=$ANNOBON_SYNC|" "$APP_DIR/.env"
    if [[ "$ANNOBON_SYNC" == "none" ]]; then
        sed -i "s|SYNC_ENABLED=.*|SYNC_ENABLED=false|" "$APP_DIR/.env"
    fi
    echo ""
    warn "Editar $APP_DIR/.env: SYNC_API_TOKEN, DATABASE_URL"
    read -p "  ¿Listo? (s/N): " C
    [[ "$C" != "s" && "$C" != "S" ]] && err "Edite .env y vuelva a ejecutar."
fi

systemctl start mysql && systemctl enable mysql
cp "$APP_DIR/deploy/mysql_bioko.cnf" /etc/mysql/conf.d/bioko.cnf
systemctl restart mysql
DB_PASS="Annobon_$(openssl rand -hex 8)"
mysql -u root -e "
CREATE DATABASE IF NOT EXISTS bioko_health CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'bioko_user'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT SELECT,INSERT,UPDATE,DELETE,CREATE,ALTER,INDEX,DROP ON bioko_health.* TO 'bioko_user'@'localhost';
FLUSH PRIVILEGES;" 2>/dev/null
sed -i "s|mysql+pymysql://bioko_user:PASSWORD_ANNOBON@localhost|mysql+pymysql://bioko_user:${DB_PASS}@localhost|" "$APP_DIR/.env"

cd "$APP_DIR"
FLASK_ENV=annobon_node "$APP_DIR/venv/bin/python" -c \
    "from app import create_app; from app.models.models import db; \
     app = create_app('annobon_node'); app.app_context().push(); db.create_all()"
FLASK_ENV=annobon_node "$APP_DIR/venv/bin/python" scripts/seed_db.py

cp "$APP_DIR/deploy/provincia/gunicorn.conf.py" "$APP_DIR/gunicorn.conf.py"
cp "$APP_DIR/deploy/instalacion/nginx" /etc/nginx/sites-available/bioko_health
sed -i "s|LAN_IP|$LAN_IP|g" /etc/nginx/sites-available/bioko_health
ln -sf /etc/nginx/sites-available/bioko_health /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

mkdir -p /var/log/bioko_health /run/bioko_health \
         "$APP_DIR/uploads" "$APP_DIR/reports" \
         "$APP_DIR/logs" "$APP_DIR/flask_sessions"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR" /var/log/bioko_health /run/bioko_health

cp "$APP_DIR/deploy/bioko_health.service" /etc/systemd/system/
systemctl daemon-reload && systemctl enable bioko_health && systemctl start bioko_health

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✓ NODO ANNOBÓN instalado — modo: $ANNOBON_SYNC"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  URL: http://$LAN_IP  o  http://salud.local                 ║"
echo "║  Usuario: admin  |  Contraseña: Bioko2024!  ← CAMBIAR YA   ║"
echo "╠══════════════════════════════════════════════════════════════╣"
warn "Conectividad con el Ministerio pendiente de definición."
warn "Configurar ANNOBON_SYNC_MODE en $APP_DIR/.env cuando se decida."
echo "╚══════════════════════════════════════════════════════════════╝"
