#!/bin/bash
# mesh_routing.sh - Объединяет сети через Bridge интерфейс

# Узнаем наш Bridge интерфейс (обычно eth0 или первый в списке)
MY_BRIDGE_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | head -n 1)

echo ">> Настройка маршрутизации (Mesh)..."
echo "Текущий сервер будет знать, как достучаться до соседей."

# Функция добавления маршрута
add_route() {
    TARGET_NET=$1
    VIA_IP=$2
    
    echo "Добавляем маршрут до $TARGET_NET через $VIA_IP..."
    
    # Добавляем в текущую сессию
    ip route add $TARGET_NET via $VIA_IP dev $MY_BRIDGE_IF
    
    # Добавляем в постоянную конфигурацию (чтобы после перезагрузки работало)
    # Создаем файл route-<interface> если нет
    ROUTE_FILE="/etc/sysconfig/network-scripts/route-$MY_BRIDGE_IF"
    
    # Проверяем, нет ли уже такого маршрута в файле
    if ! grep -q "$TARGET_NET" "$ROUTE_FILE" 2>/dev/null; then
        echo "$TARGET_NET via $VIA_IP dev $MY_BRIDGE_IF" >> $ROUTE_FILE
        echo "Маршрут сохранен в $ROUTE_FILE"
    fi
}

echo "--- Введи данные СОСЕДА 1 ---"
read -p "IP адрес сети соседа (например 20.0.10.0/24): " NET1
read -p "Bridge IP адрес соседа (например 192.168.1.102): " GW1

add_route $NET1 $GW1

echo "--- Введи данные СОСЕДА 2 ---"
read -p "IP адрес сети соседа (например 30.0.10.0/24): " NET2
read -p "Bridge IP адрес соседа (например 192.168.1.103): " GW2

add_route $NET2 $GW2

echo ">> Готово! Проверяем таблицу маршрутов:"
ip route
