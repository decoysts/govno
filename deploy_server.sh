#!/bin/bash
# deploy_server.sh 1 (или 2, или 3)

NET_ID=$1

if [ -z "$NET_ID" ]; then
  echo "Укажи ID сети: 1, 2 или 3"
  exit 1
fi

# Настройки IP
INTERNAL_IP="10.0.10.1" # Дефолт
VPN_SUBNET="10.8.1.0"

if [ "$NET_ID" == "1" ]; then
    INTERNAL_IP="10.0.10.1"
    VPN_SUBNET="10.8.1.0"
elif [ "$NET_ID" == "2" ]; then
    INTERNAL_IP="20.0.10.1"
    VPN_SUBNET="10.8.2.0"
elif [ "$NET_ID" == "3" ]; then
    INTERNAL_IP="30.0.10.1"
    VPN_SUBNET="10.8.3.0"
fi

echo ">> Настройка статического IP $INTERNAL_IP на enp0s8 (Адаптер 2)..."
# Внимание: имя интерфейса может отличаться (eth1, enp0s8). Проверь ip a
IFACE_INT=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed -n '2p') # Берет второй интерфейс

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE_INT
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE_INT
DEVICE=$IFACE_INT
ONBOOT=yes
IPADDR=$INTERNAL_IP
PREFIX=24
EOF

systemctl restart network

echo ">> Конфиг OpenVPN Server..."
mkdir -p /etc/openvpn/server
cat <<EOF > /etc/openvpn/server/server.conf
port 1194
proto udp
dev tun
ca ca.crt
cert server$NET_ID.crt
key server$NET_ID.key
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

echo ">> Настройка NAT (Iptables)..."
# Получаем имя WAN интерфейса (первый адаптер)
IFACE_WAN=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)

iptables -t nat -F
iptables -t nat -A POSTROUTING -s $VPN_SUBNET/24 -o $IFACE_WAN -j MASQUERADE
iptables -t nat -A POSTROUTING -s ${INTERNAL_IP%.*}.0/24 -o $IFACE_WAN -j MASQUERADE
service iptables save

echo ">> Готово! Не забудь скопировать сертификаты (ca.crt, server$NET_ID.crt, server$NET_ID.key, dh.pem, ta.key) в /etc/openvpn/server/ и запустить: systemctl start openvpn-server@server"
