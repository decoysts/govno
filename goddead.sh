#!/bin/bash
# god_mode.sh v3.0 - Fix IP Vanishing
# Использование: ./god_mode.sh <РОЛЬ> <ID_СЕТИ>

ROLE=$1
ID=$2

# === [1] ПРОВЕРКИ И НАСТРОЙКИ ===
if [[ -z "$ROLE" || -z "$ID" ]]; then
    echo "ОШИБКА! Формат: ./god_mode.sh [server|client] [1|2|3]"
    exit 1
fi

# Пути
PKI_DIR="/etc/openvpn/easy-rsa/pki"
EASY_RSA_DIR="/etc/openvpn/easy-rsa"

# Определение подсетей
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

# IP АДРЕСА (СЕРВЕР = .5, КЛИЕНТ = .2)
SERVER_IP="${NET_PREFIX}.5"
CLIENT_IP="${NET_PREFIX}.2"

# Поиск интерфейса
IFACE_INT=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed -n '2p')
if [ -z "$IFACE_INT" ]; then
    # Фолбек: пробуем найти enp0s8 явно
    if ip link show enp0s8 > /dev/null 2>&1; then
        IFACE_INT="enp0s8"
    else
        echo "ОШИБКА: Не найден второй адаптер! Проверь настройки VirtualBox."
        exit 1
    fi
fi
echo ">> Работаем с интерфейсом: $IFACE_INT"

# Функция жесткого перезапуска сети
hard_restart_net() {
    local IP_ADDR=$1
    local GW=$2
    
    echo ">> [NETWORK] Flush IP..."
    ip addr flush dev $IFACE_INT
    
    echo ">> [NETWORK] Link Down/Up..."
    ip link set $IFACE_INT down
    ip link set $IFACE_INT up
    
    echo ">> [NETWORK] Restarting Service..."
    systemctl restart network
    
    # СТРАХОВКА: Если IP не появился через 2 секунды, прибиваем его гвоздями
    sleep 2
    CURRENT_IP=$(ip a show $IFACE_INT | grep "inet ")
    if [[ -z "$CURRENT_IP" ]]; then
        echo ">> [WARNING] Network service тупит. Назначаю IP вручную!"
        ip addr add $IP_ADDR/24 dev $IFACE_INT
        ip link set $IFACE_INT up
    fi
    
    # Проверка
    echo ">> [STATUS] Текущий IP на $IFACE_INT:"
    ip a show $IFACE_INT | grep inet
}


# === [2] ЛОГИКА ДЛЯ СЕРВЕРА ===
if [ "$ROLE" == "server" ]; then
    echo ">>> НАСТРОЙКА SERVER (Net $ID) -> IP $SERVER_IP <<<"
    
    # 2.1 Настройка конфига сети
    cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE_INT
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE_INT
DEVICE=$IFACE_INT
ONBOOT=yes
IPADDR=$SERVER_IP
PREFIX=24
NM_CONTROLLED=no
EOF
    
    # Жесткий рестарт
    hard_restart_net $SERVER_IP

    # 2.2 Копирование ключей
    echo ">> [VPN] Настройка ключей..."
    mkdir -p /etc/openvpn/server
    cp $PKI_DIR/ca.crt /etc/openvpn/server/
    cp $PKI_DIR/dh.pem /etc/openvpn/server/
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

    # 2.4 NAT & Firewall
    echo ">> [FIREWALL] Открываем порты..."
    echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ipforward.conf
    sysctl -p /etc/sysctl.d/99-ipforward.conf > /dev/null
    
    IFACE_WAN=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    
    systemctl stop firewalld
    systemctl disable firewalld
    systemctl start iptables
    
    # Чистим и добавляем правила
    iptables -t nat -F
    iptables -t nat -A POSTROUTING -s $VPN_SUBNET/24 -o $IFACE_WAN -j MASQUERADE
    iptables -t nat -A POSTROUTING -s ${NET_PREFIX}.0/24 -o $IFACE_WAN -j MASQUERADE
    iptables -I INPUT -p udp --dport 1194 -j ACCEPT
    service iptables save

    # 2.5 Запуск
    echo ">> [VPN] Start..."
    systemctl enable openvpn-server@server
    systemctl restart openvpn-server@server
    echo ">> ГОТОВО. IP: $SERVER_IP"

# === [3] ЛОГИКА ДЛЯ КЛИЕНТА ===
elif [ "$ROLE" == "client" ]; then
    echo ">>> НАСТРОЙКА CLIENT (Net $ID) -> IP $CLIENT_IP <<<"

    # 3.1 Настройка сети
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
NM_CONTROLLED=no
EOF
    
    # Жесткий рестарт
    hard_restart_net $CLIENT_IP $SERVER_IP
    
    echo ">> Чистим ARP таблицу..."
    ip neigh flush all

    # 3.2 Генерация конфига
    echo ">> [VPN] Генерируем конфиг..."
    CA_DATA=$(cat $PKI_DIR/ca.crt)
    CERT_DATA=$(cat $PKI_DIR/issued/client$ID.crt)
    KEY_DATA=$(cat $PKI_DIR/private/client$ID.key)
    
    if [ -f "$EASY_RSA_DIR/ta.key" ]; then TA_DATA=$(cat $EASY_RSA_DIR/ta.key); else TA_DATA=$(cat $PKI_DIR/ta.key); fi

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
    echo ">> [VPN] Запуск клиента..."
    systemctl enable openvpn@client
    systemctl restart openvpn@client
    
    echo ">> Ждем поднятия туннеля (5 сек)..."
    sleep 5
    ping -c 2 8.8.8.8
    if [ $? -eq 0 ]; then
        echo ">> УСПЕХ! ИНТЕРНЕТ ЕСТЬ!"
    else
        echo ">> ПРОВЕРЬ: ping $SERVER_IP (должен работать)"
    fi

else
    echo "Роли: server, client"
    exit 1
fi
