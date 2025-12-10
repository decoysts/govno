#!/bin/bash
# god_mode.sh - Один скрипт, чтобы править всеми
# Использование: ./god_mode.sh <РОЛЬ> <ID_СЕТИ>
# Пример Server: ./god_mode.sh server 1
# Пример Client: ./god_mode.sh client 1

ROLE=$1
ID=$2

# === [1] ПРОВЕРКИ И НАСТРОЙКИ ===
if [[ -z "$ROLE" || -z "$ID" ]]; then
    echo "ОШИБКА! Формат: ./god_mode.sh [server|client] [1|2|3]"
    exit 1
fi

# Пути (т.к. мы клоны CA, ключи уже тут)
PKI_DIR="/etc/openvpn/easy-rsa/pki"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"

# Определение подсетей по ID
if [ "$ID" == "1" ]; then
    NET_PREFIX="10.0.10"
    VPN_SUBNET="10.8.1.0"
elif [ "$ID" == "2" ]; then
    NET_PREFIX="20.0.10"
    VPN_SUBNET="10.8.2.0"
elif [ "$ID" == "3" ]; then
    NET_PREFIX="30.0.10"
    VPN_SUBNET="10.8.3.0"
else
    echo "ID должен быть 1, 2 или 3"
    exit 1
fi

SERVER_IP="${NET_PREFIX}.1"
CLIENT_IP="${NET_PREFIX}.2" # Клиент всегда будет .2

# Поиск второго интерфейса (для локалки)
# Берем второй интерфейс из списка (обычно enp0s8 или eth1)
IFACE_INT=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed -n '2p')
if [ -z "$IFACE_INT" ]; then
    echo "ОШИБКА: Не найден второй сетевой адаптер для внутренней сети!"
    exit 1
fi
echo ">> Работаем с интерфейсом: $IFACE_INT"

# === [2] ЛОГИКА ДЛЯ СЕРВЕРА ===
if [ "$ROLE" == "server" ]; then
    echo ">>> НАСТРОЙКА SERVER (Net $ID) <<<"
    
    # 2.1 Настройка сети
    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE_INT
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE_INT
DEVICE=$IFACE_INT
ONBOOT=yes
IPADDR=$SERVER_IP
PREFIX=24
EOF
    systemctl restart network

    # 2.2 Копирование ключей
    mkdir -p /etc/openvpn/server
    cp $PKI_DIR/ca.crt /etc/openvpn/server/
    cp $PKI_DIR/dh.pem /etc/openvpn/server/
    # Ищем ta.key
    [ -f "$EASY_RSA_DIR/ta.key" ] && cp $EASY_RSA_DIR/ta.key /etc/openvpn/server/ || cp $PKI_DIR/ta.key /etc/openvpn/server/
    
    cp $PKI_DIR/issued/server$ID.crt /etc/openvpn/server/
    cp $PKI_DIR/private/server$ID.key /etc/openvpn/server/

    # 2.3 Конфиг Server
    cat <<EOF > /etc/openvpn/server/server.conf
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

    # 2.4 NAT
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ipforward.conf
    sysctl -p /etc/sysctl.d/99-ipforward.conf > /dev/null
    # Находим WAN интерфейс (где есть инет)
    IFACE_WAN=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)
    
    systemctl start iptables
    iptables -t nat -F
    iptables -t nat -A POSTROUTING -s $VPN_SUBNET/24 -o $IFACE_WAN -j MASQUERADE
    iptables -t nat -A POSTROUTING -s ${NET_PREFIX}.0/24 -o $IFACE_WAN -j MASQUERADE
    service iptables save

    # 2.5 Запуск
    systemctl enable openvpn-server@server
    systemctl restart openvpn-server@server
    echo ">> СЕРВЕР ГОТОВ. IP: $SERVER_IP"

# === [3] ЛОГИКА ДЛЯ КЛИЕНТА ===
elif [ "$ROLE" == "client" ]; then
    echo ">>> НАСТРОЙКА CLIENT (Net $ID) <<<"

    # 3.1 Настройка сети (Шлюз = IP Сервера)
    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE_INT
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE_INT
DEVICE=$IFACE_INT
ONBOOT=yes
IPADDR=$CLIENT_IP
PREFIX=24
GATEWAY=$SERVER_IP
DNS1=8.8.8.8
EOF
    systemctl restart network
    echo ">> Сеть перезапущена. Ждем 5 сек..."
    sleep 5

    # 3.2 Генерация конфига из локальных ключей
    # Читаем содержимое файлов в переменные
    CA_DATA=$(cat $PKI_DIR/ca.crt)
    CERT_DATA=$(cat $PKI_DIR/issued/client$ID.crt)
    KEY_DATA=$(cat $PKI_DIR/private/client$ID.key)
    
    if [ -f "$EASY_RSA_DIR/ta.key" ]; then
        TA_DATA=$(cat $EASY_RSA_DIR/ta.key)
    else
        TA_DATA=$(cat $PKI_DIR/ta.key)
    fi

    # Собираем единый файл
    cat <<EOF > /etc/openvpn/client.conf
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
key-direction 1
<ca>
$CA_DATA
</ca>
<cert>
$CERT_DATA
</cert>
<key>
$KEY_DATA
</key>
<tls-auth>
$TA_DATA
</tls-auth>
EOF

    # 3.3 Запуск
    echo ">> Запускаем OpenVPN клиент..."
    systemctl enable openvpn@client
    systemctl restart openvpn@client
    
    echo ">> КЛИЕНТ ГОТОВ. IP: $CLIENT_IP. Шлюз: $SERVER_IP"
    echo ">> Пробуем пинг гугла через туннель..."
    sleep 3
    ping -c 2 8.8.8.8
else
    echo "Неверная роль! Используй 'server' или 'client'"
    exit 1
fi
