### Список хостов:
- NFS-сервер: 10.10.2.121
- клиент: 10.11.1.119
### Задание №1. Настройка NFS и монтирование директории.
#### Установка пакетов `nfs-kernel-server` и `nfs-common` на сервере.
```
sudo apt update
sudo apt install nfs-kernel-server nfs-common
```
#### Cоздание общей директории `/srv/share/nfs`.
```
sudo mkdir -p /srv/shares/nfs
sudo chown ${USER}:${USER} -R /srv/shares/nfs/
```
#### Редактирование конфигурационного файла `/etc/exports` так, чтобы директория `/srv/share/nfs` стала доступной для подсети виртуальных машин с правами на чтение и запись.
```
sudo vim /etc/exports
/srv/shares/nfs 10.0.0.0/8(rw,sync,no_subtree_check)
```
#### Перечитать и применить изменения в конфигурационном файле `/etc/exports`:
```
sudo exportfs -a
```
#### Запуск службы NFS
```
sudo systemctl start nfs-kernel-server
sudo systemctl enable nfs-kernel-server
```
#### Проверка доступа к NFS
Для проверки настроек NFS и доступности директорий для монтирования используйте `showmount`:
```
showmount -e localhost
```
#### Установка пакета `nfs-common` на клиенте.
```
sudo apt update
sudo apt install nfs-common -y
```
#### Создание каталога `/mnt/share` — он станет точкой монтирования для NFS.
```
sudo mkdir -p /mnt/share
sudo chown ${USER}:${USER} -R /mnt/share/ 
```
#### Примонтировать удалённую директорию `/srv/share/nfs`, которая находится на первой виртуальной машине (NFS-сервере).
```
sudo mount -t nfs 10.10.2.121:/srv/shares/nfs /mnt/share
```
#### Создать файл `nfs-practice` в каталоге `/mnt/share`.
```
touch /mnt/share/nfs-practice
```
#### Настройка автомонтирования директории.
Нужно добавить на клиентской машине соответствующую запись в файл `/etc/fstab`:
```
echo "10.10.2.121:/srv/shares/nfs /mnt/share nfs defaults 0 0" | sudo tee -a /etc/fstab
```
### Вывод:
1. Вывод конфигурационного файла `/etc/exports`:
```
# /etc/exports: the access control list for filesystems which may be exported
#               to NFS clients.  See exports(5).
#
# Example for NFSv2 and NFSv3:
# /srv/homes       hostname1(rw,sync,no_subtree_check) hostname2(ro,sync,no_subtree_check)
#
# Example for NFSv4:
# /srv/nfs4        gss/krb5i(rw,sync,fsid=0,crossmnt,no_subtree_check)
# /srv/nfs4/homes  gss/krb5i(rw,sync,no_subtree_check)
#
/srv/shares/nfs 10.0.0.0/8(rw,sync,no_subtree_check)
```
2. Вывод команды `showmount -e localhost` с серверной машины. 
```
Export list for localhost:
/srv/shares/nfs 10.0.0.0/8
```
3. Вывод команды `ls -l` для примонтированной директории на клиентской машине.
```
s22157660@s22157660-02:~$ la -l /mnt/share/
total 0
-rw-rw-r-- 1 s22157660 s22157660 0 May 13 08:56 nfs-practice
```
4. Вывод файла `/etc/fstab`
```
s22157660@s22157660-02:~$ cat /etc/fstab
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/vda2 during curtin installation
/dev/disk/by-uuid/ed465c6e-049a-41c6-8e0b-c8da348a3577 / ext4 defaults 0 1
10.10.2.121:/srv/shares/nfs /mnt/share nfs defaults 0 0
```
