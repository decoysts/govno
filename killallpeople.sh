#!/bin/bash
# master_setup.sh
# Использование: ./master_setup.sh <РОЛЬ> <НОМЕР_СЕТИ>
# Пример: ./master_setup.sh server 1

ROLE=$1
ID=$2

# === ПРОВЕРКИ ===
if [ -z "$ROLE" ] || [ -z "$ID" ]; then
    echo "ОШИБКА! Используй формат: ./master_setup.sh server 1"
    echo "Доступные роли: server"
    echo "Доступные ID: 1, 2, 3"
    exit 1
fi

# Пути к ключам (они уже есть на диске после клонирования CA)
PKI_DIR="/etc/openvpn/easy-rsa/pki"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"
SERVER_CONF_DIR="/etc/openvpn/server"

# Настройки IP (Жестко задаем .1 шлюзом, чтобы не было путаницы)
if [ "$ID" == "1" ]; then
    INTERNAL_IP="10.0.10.1"
    VPN_SUBNET="10.8.1.0"
elif [ "$ID" == "2" ]; then
    INTERNAL_IP="20.0.10.1"
    VPN_SUBNET="10.8.2.0"
elif [ "$ID" == "3" ]; then
    INTERNAL_IP="30.0.10.1"
    VPN_SUBNET="10.8.3.0"
else
    echo "Неверный ID сети (только 1, 2, 3)"
    exit 1
fi

echo ">>> НАЧИНАЕМ НАСТРОЙКУ SERVER $ID (Net: $INTERNAL_IP) <<<"

# 1. КОПИРОВАНИЕ КЛЮЧЕЙ
echo "[1/4] Копируем сертификаты из локальных папок..."
mkdir -p $SERVER_CONF_DIR

# Копируем CA
cp $PKI_DIR/ca.crt $SERVER_CONF_DIR/
# Копируем DH
cp $PKI_DIR/dh.pem $SERVER_CONF_DIR/
# Копируем ta.key (он обычно в корне easy-rsa или в pki, ищем везде)
if [ -f "$EASY_RSA_DIR/ta.key" ]; then
    cp $EASY_RSA_DIR/ta.key $SERVER_CONF_DIR/
elif [ -f "$PKI_DIR/ta.key" ]; then
    cp $PKI_DIR/ta.key $SERVER_CONF_DIR/
else
    # Если вдруг нет ta.key, генерим новый, похуй
    openvpn --genkey --secret $SERVER_CONF_DIR/ta.key
fi

# Копируем пару ключей сервера
cp $PKI_DIR/issued/server$ID.crt $SERVER_CONF_DIR/
cp $PKI_DIR/private/server$ID.key $SERVER_CONF_DIR/

# Проверка
if [ ! -f "$SERVER_CONF_DIR/server$ID.key" ]; then
    echo "ОШИБКА: Не найден ключ server$ID.key! Ты точно генерировал его на CA?"
    ls $PKI_DIR/private/
    exit 1
fi

# 2. НАСТРОЙКА СЕТИ (Внутренний адаптер)
echo "[2/4] Настройка сетевого адаптера..."
# Ищем второй интерфейс (не тот который с инетом)
IFACE_INT=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed -n '2p')

# Если вдруг нашел virbr0 или другую херню, пробуем грубый метод
if [[ "$IFACE_INT" == *"virbr"* ]] || [[ -z "$IFACE_INT" ]]; then
   # Берем просто второй по счету интерфейс, который начинается на e (eth, enp)
   IFACE_INT=$(ls /sys/class/net/ | grep "^e" | sed -n '2p')
fi

echo "Выбран интерфейс для локалки: $IFACE_INT"

# Пишем конфиг сети
cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE_INT
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE_INT
DEVICE=$IFACE_INT
ONBOOT=yes
IPADDR=$INTERNAL_IP
PREFIX=24
EOF

# Передергиваем сеть
systemctl restart network
sleep 3

# 3. КОНФИГ OPENVPN
echo "[3/4] Создаем конфиг OpenVPN..."
cat <<EOF > $SERVER_CONF_DIR/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server$ID.crt
key server$ID.key
dh dh.pem
tls-auth ta.key 0
server $VPN_SUBNET 255.255.255.0
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-CBC
persist-key
persist-tun
status openvpn-status.log
verb 3
explicit-exit-notify 1
EOF

# 4. NAT И FORWARDING
echo "[4/4] Настройка NAT..."
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf > /dev/null

# Определяем WAN интерфейс (где интернет)
IFACE_WAN=$(ip route get 8.8.8.8 | awk '{print $5; exit}')

systemctl stop firewalld
systemctl disable firewalld
systemctl enable iptables
systemctl start iptables
iptables -t nat -F
iptables -t nat -A POSTROUTING -s $VPN_SUBNET/24 -o $IFACE_WAN -j MASQUERADE
iptables -t nat -A POSTROUTING -s ${INTERNAL_IP%.*}.0/24 -o $IFACE_WAN -j MASQUERADE
service iptables save

# Запуск
systemctl enable openvpn-server@server
systemctl restart openvpn-server@server

echo ">>> ГОТОВО! СЕРВЕР $ID РАБОТАЕТ <<<"
echo "IP внутр: $INTERNAL_IP"
echo "VPN подсеть: $VPN_SUBNET"
