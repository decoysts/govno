#!/bin/bash
# bridge_mesh.sh - Роутинг через существующий мост
# Использование: ./bridge_mesh.sh <МОЙ_ID> <IP_SRV_1> <IP_SRV_2> <IP_SRV_3>

MY_ID=$1
IP_S1=$2
IP_S2=$3
IP_S3=$4

if [[ -z "$IP_S1" || -z "$IP_S2" ]]; then
    echo "ОШИБКА! Нужно указать ID и IP серверов."
    echo "Пример: ./bridge_mesh.sh 1 192.168.1.10 192.168.1.20 192.168.1.30"
    exit 1
fi

# Находим интерфейс, на котором висит сеть 192.168.* (чтобы через него слать)
BRIDGE_IFACE=$(ip -o addr show | grep "192.168" | awk '{print $2}' | head -1)

if [ -z "$BRIDGE_IFACE" ]; then
    echo "ОШИБКА: Не найден интерфейс с IP 192.168.x.x!"
    exit 1
fi

echo ">>> НАСТРОЙКА РОУТИНГА (Я = Server $MY_ID) через $BRIDGE_IFACE <<<"

# Функция добавления маршрута
add_route() {
    local TARGET_ID=$1
    local TARGET_GW=$2
    
    # Не прокладываем маршрут к самому себе
    if [ "$MY_ID" == "$TARGET_ID" ] || [ -z "$TARGET_GW" ]; then return; fi

    local TARGET_NET="10.8.${TARGET_ID}.0/24"
    
    echo ">> [ROUTE] К сети $TARGET_NET через шлюз $TARGET_GW"
    
    # 1. Добавляем системный маршрут (чтобы сервер знал путь)
    ip route add $TARGET_NET via $TARGET_GW dev $BRIDGE_IFACE 2>/dev/null
    
    # 2. Пушим маршрут клиентам (чтобы клиенты знали путь)
    local CONF="/etc/openvpn/server/server.conf"
    local PUSH="push \"route 10.8.${TARGET_ID}.0 255.255.255.0\""
    
    if ! grep -Fq "$PUSH" $CONF; then
        echo "$PUSH" >> $CONF
        echo "   -> Добавлено в конфиг OpenVPN"
    fi
}

# Магия циклов не нужна, пропишем явно для надежности
add_route 1 "$IP_S1"
add_route 2 "$IP_S2"
add_route 3 "$IP_S3"

# 3. Разрешаем форвардинг пакетов между разными VPN подсетями
echo ">> [FIREWALL] Разрешаем трафик между VPN-сетями..."
# Разрешаем все, что идет из 10.8.x.x в 10.8.x.x
iptables -I FORWARD -s 10.8.0.0/16 -d 10.8.0.0/16 -j ACCEPT
service iptables save > /dev/null

# 4. Рестарт для применения конфигов
echo ">> [RESTART] Перезагрузка OpenVPN..."
systemctl restart openvpn-server@server

echo ">>> ГОТОВО! Переподключи клиентов."
