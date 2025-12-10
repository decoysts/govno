#!/bin/bash
# deploy_client_machine.sh 1 (для Net1) и т.д.

NET_ID=$1
if [ -z "$NET_ID" ]; then echo "Укажи ID сети: 1, 2 или 3"; exit 1; fi

INTERNAL_IP=""
GATEWAY_IP=""

if [ "$NET_ID" == "1" ]; then
    INTERNAL_IP="10.0.10.10"
    GATEWAY_IP="10.0.10.1"
elif [ "$NET_ID" == "2" ]; then
    INTERNAL_IP="20.0.10.10"
    GATEWAY_IP="20.0.10.1"
elif [ "$NET_ID" == "3" ]; then
    INTERNAL_IP="30.0.10.10"
    GATEWAY_IP="30.0.10.1"
fi

echo ">> Настройка сети клиента (только внутренняя)..."
# Предполагаем, что у клиента только 1 адаптер (внутренний), или второй отключен
IFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)

cat <<EOF > /etc/sysconfig/network-scripts/ifcfg-$IFACE
TYPE=Ethernet
BOOTPROTO=static
NAME=$IFACE
DEVICE=$IFACE
ONBOOT=yes
IPADDR=$INTERNAL_IP
PREFIX=24
GATEWAY=$GATEWAY_IP
DNS1=8.8.8.8
EOF

systemctl restart network
echo ">> Сеть настроена. Теперь установи OpenVPN и скопируй конфиг клиента (.ovpn) с сервера."
