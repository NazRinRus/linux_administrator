### Обновление ядра Linux
Цель: Установить на виртуальную машину ОС `Ubuntu 24.04.3 LTS`, обновить версию ядра
#### Текущая конфигурация ОС
1. Версия ОС:
```
nazrinrus@pg-node1:~$ cat /etc/os-release
PRETTY_NAME="Ubuntu 24.04.3 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.3 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
LOGO=ubuntu-logo
```
2. Версия ядра:
```
nazrinrus@pg-node1:~$ uname -r
6.8.0-85-generic
```
#### Процесс обновления
```
mkdir /tmp/kernel && cd /tmp/kernel
wget https://kernel.ubuntu.com/mainline/v6.19.10/amd64/linux-headers-6.19.10-061910-generic_6.19.10-061910.202603251147_amd64.deb
wget https://kernel.ubuntu.com/mainline/v6.19.10/amd64/linux-headers-6.19.10-061910_6.19.10-061910.202603251147_all.deb
wget https://kernel.ubuntu.com/mainline/v6.19.10/amd64/linux-image-unsigned-6.19.10-061910-generic_6.19.10-061910.202603251147_amd64.deb
wget https://kernel.ubuntu.com/mainline/v6.19.10/amd64/linux-modules-6.19.10-061910-generic_6.19.10-061910.202603251147_amd64.deb
sudo dpkg -i *.deb 
```
Проверить что ядро появилось в `/boot`
```
ls -al /boot

lrwxrwxrwx  1 root root       30 Apr  2 08:39 vmlinuz -> vmlinuz-6.19.10-061910-generic
-rw-------  1 root root 16978432 Mar 25 11:47 vmlinuz-6.19.10-061910-generic
-rw-------  1 root root 14948744 Aug  2  2024 vmlinuz-6.8.0-41-generic
-rw-------  1 root root 15026568 Sep 18  2025 vmlinuz-6.8.0-85-generic
lrwxrwxrwx  1 root root       24 Apr  2 08:39 vmlinuz.old -> vmlinuz-6.8.0-85-generic
```
После перезагрузки, проверить версию ядра:
```
nazrinrus@pg-node1:~$ uname -r
6.19.10-061910-generic
```
