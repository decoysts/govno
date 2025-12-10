#!/bin/bash
# gen_client_ovpn.sh
# Использование: ./gen_client_ovpn.sh <ИМЯ_КЛИЕНТА> <IP_СЕРВЕРА>
# Пример: ./gen_client_ovpn.sh client1 10.0.10.1

CLIENT_NAME=$1
SERVER_IP=$2
KEYS_DIR="/etc/openvpn/server"
OUTPUT_DIR="/root/client-configs"

if [ -z "$CLIENT_NAME" ] || [ -z "$SERVER_IP" ]; then
    echo "Ошибка! Укажи имя клиента и внутренний IP сервера."
    echo "Пример: ./gen_client_ovpn.sh client1 10.0.10.1"
    exit 1
fi

mkdir -p $OUTPUT_DIR

# Пути к ключам (проверь, что они там лежат!)
CA="$KEYS_DIR/ca.crt"
CERT="$KEYS_DIR/$CLIENT_NAME.crt"
KEY="$KEYS_DIR/$CLIENT_NAME.key"
TA="$KEYS_DIR/ta.key"

if [ ! -f "$CERT" ]; then
    echo "Ключ $CERT не найден! Сначала скопируй ключи с CA-машины."
    exit 1
fi

echo ">> Генерация конфига для $CLIENT_NAME..."

cat <<EOF > $OUTPUT_DIR/$CLIENT_NAME.ovpn
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
cipher AES-256-CBC
verb 3
key-direction 1
# Все сертификаты внутри файла:
<ca>
$(cat $CA)
</ca>
<cert>
$(cat $CERT)
</cert>
<key>
$(cat $KEY)
</key>
<tls-auth>
$(cat $TA)
</tls-auth>
EOF

echo ">> Файл создан: $OUTPUT_DIR/$CLIENT_NAME.ovpn"
echo ">> Теперь просто перекинь этот ОДИН файл на машину клиента."
