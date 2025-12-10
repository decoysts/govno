#!/bin/bash
# base_setup.sh - Базовая настройка для всех узлов

echo ">> [1/5] Фиксим репозитории CentOS 7 (Vault)..."
sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*

echo ">> [2/5] Обновление и установка пакетов..."
yum install -y epel-release
yum install -y openvpn easy-rsa net-tools vim iptables-services bridge-utils wget

echo ">> [3/5] Отключаем SELinux и Firewalld (ставим iptables)..."
setenforce 0
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
systemctl stop firewalld
systemctl disable firewalld
systemctl enable iptables
systemctl start iptables

echo ">> [4/5] Включаем IP Forwarding..."
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-ipforward.conf
sysctl -p /etc/sysctl.d/99-ipforward.conf

echo ">> [5/5] Готово! Перезагрузись на всякий случай."
