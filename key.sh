#!/bin/bash
# setup_ca_pki.sh - Генерация всех ключей в одном месте

EASY_RSA_DIR="/etc/openvpn/easy-rsa"
mkdir -p /etc/openvpn
cp -r /usr/share/easy-rsa/3/ $EASY_RSA_DIR
cd $EASY_RSA_DIR

echo ">> Инициализация PKI..."
./easyrsa init-pki

echo ">> Создание CA (Придумай пароль и запомни!)..."
# nopass чтобы не вводить пароль при старте сервисов, но для CA лучше с паролем.
# Тут делаем без пароля для полной автоматизации процесса
./easyrsa build-ca nopass

echo ">> Генерация ключей для Серверов..."
./easyrsa build-server-full server1 nopass
./easyrsa build-server-full server2 nopass
./easyrsa build-server-full server3 nopass

echo ">> Генерация ключей для Клиентов..."
./easyrsa build-client-full client1 nopass
./easyrsa build-client-full client2 nopass
./easyrsa build-client-full client3 nopass

echo ">> Генерация Diffie-Hellman (это долго, жди)..."
./easyrsa gen-dh

echo ">> Создание HMAC ключа (ta.key)..."
openvpn --genkey --secret ta.key

echo ">> ВСЕ ГОТОВО. Теперь нужно раскидать ключи по машинам!"
echo "Ключи лежат в $EASY_RSA_DIR/pki/issued и private"
