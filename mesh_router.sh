#!/bin/bash
# mesh_router.sh - Объединение сетей (Static Routing)
# Запускать на каждом сервере!

# 1. Авто-определение Bridge интерфейса (где интернет)
IFACE_WAN=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
MY_WAN_IP=$(ip -o -4 addr list $IFACE_WAN | awk '{print $4}' | cut -d/ -f1)

echo "=============================================="
echo "      НАСТРОЙКА МАРШРУТИЗАЦИИ (MESH)          "
echo "=============================================="
echo "Мой WAN интерфейс: $IFACE_WAN"
echo "Мой WAN IP: $MY_WAN_IP"
echo "----------------------------------------------"

# Функция добавления маршрута
add_mesh_route() {
    TARGET_NET=$1
    NEIGHBOR_IP=$2
    
    # Проверки на дурака
    if [[ -z "$TARGET_NET" || -z "$NEIGHBOR_IP" ]]; then
        echo "Ошибка: Данные не введены."
        return
    fi
    
    echo ">> Добавляю маршрут к $TARGET_NET через $NEIGHBOR_IP..."
    
    # 1. Добавляем маршрут в текущую сессию
    ip route add $TARGET_NET via $NEIGHBOR_IP dev $IFACE_WAN 2>/dev/null
    
    # 2. Сохраняем навечно (в route-enp0s3)
    ROUTE_FILE="/etc/sysconfig/network-scripts/route-$IFACE_WAN"
    # Удаляем старую запись если была, чтобы не дублировать
    sed -i "/$TARGET_NET/d" $ROUTE_FILE 2>/dev/null
    # Пишем новую
    echo "$TARGET_NET via $NEIGHBOR_IP dev $IFACE_WAN" >> $ROUTE_FILE
    
    # 3. Разрешаем трафик в Firewall (Forwarding)
    echo ">> Разрешаю прохождение трафика от $TARGET_NET..."
    iptables -I FORWARD -s $TARGET_NET -j ACCEPT
    iptables -I FORWARD -d $TARGET_NET -j ACCEPT
    service iptables save > /dev/null
}

echo "Введи данные ДВУХ других серверов-соседей."
echo "Пример: Если я Server 1 (10.0.10.0), то сосед - это 20.0.10.0/24"

echo ""
echo "--- СОСЕД 1 ---"
read -p "IP Сеть соседа (например 20.0.10.0/24): " NET1
read -p "Bridge IP соседа (например 192.168.1.105): " GW1
add_mesh_route $NET1 $GW1

echo ""
echo "--- СОСЕД 2 ---"
read -p "IP Сеть соседа (например 30.0.10.0/24): " NET2
read -p "Bridge IP соседа (например 192.168.1.106): " GW2
add_mesh_route $NET2 $GW2

echo ""
echo "=============================================="
echo "ГОТОВО! Таблица маршрутов:"
ip route | grep via
echo "=============================================="
