### Работа с LVM
#### Задачи
1. Уменьшить том под `/` до 8G.
2. Выделить том под `/var` - сделать в mirror.
3. Выделить том под `/home`.
4. `/home` - сделать том для снапшотов.
5. Прописать монтирование в `fstab`. Попробовать с разными опциями и разными файловыми системами (на выбор).
6. Работа со снапшотами:
- сгенерить файлы в `/home/`;
- снять снапшот;
- удалить часть файлов;
- восстановиться со снапшота

#### Состояние дискового пространства по умолчанию
```
nazrinrus@testhost:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   40G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   38G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0   19G  0 lvm  /
sdb                         8:16   0   10G  0 disk 
sdc                         8:32   0   10G  0 disk 
sdd                         8:48   0   10G  0 disk 
sde                         8:64   0   10G  0 disk 
sr0                        11:0    1 1024M  0 rom  

nazrinrus@testhost:~$ sudo lvmdiskscan
  /dev/sda2 [       2.00 GiB] 
  /dev/sda3 [     <38.00 GiB] LVM physical volume
  /dev/sdb  [      10.00 GiB] 
  /dev/sdc  [      10.00 GiB] 
  /dev/sdd  [      10.00 GiB] 
  /dev/sde  [      10.00 GiB] 
  4 disks
  1 partition
  0 LVM physical volume whole disks
  1 LVM physical volume
```

#### Реализация
1. Уменьшить том под `/` до 8G.
- Потребуется создать том для переноса раздела `/`:
```
nazrinrus@testhost:~$ sudo pvcreate /dev/sdb
  Physical volume "/dev/sdb" successfully created.
nazrinrus@testhost:~$ sudo vgcreate vg_root /dev/sdb
  Volume group "vg_root" successfully created
nazrinrus@testhost:~$ sudo lvcreate -n lv_root -l +100%FREE /dev/vg_root
  Logical volume "lv_root" created.
```
- Создать файловую систему и смонтировать:
```
nazrinrus@testhost:~$ sudo mkfs.ext4 /dev/vg_root/lv_root
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2620416 4k blocks and 655360 inodes
Filesystem UUID: db379479-3b87-48ea-9d4a-f3015cef6fc2
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

nazrinrus@testhost:~$ sudo mount /dev/vg_root/lv_root /mnt
nazrinrus@testhost:~$ df -h
Filesystem                         Size  Used Avail Use% Mounted on
tmpfs                              392M  1.1M  391M   1% /run
/dev/mapper/ubuntu--vg-ubuntu--lv   19G  6.4G   12G  37% /
tmpfs                              2.0G     0  2.0G   0% /dev/shm
tmpfs                              5.0M     0  5.0M   0% /run/lock
/dev/sda2                          2.0G  104M  1.7G   6% /boot
tmpfs                              392M   12K  392M   1% /run/user/1000
/dev/mapper/vg_root-lv_root        9.8G   24K  9.3G   1% /mnt
```
- Копирование данных:
```
rsync -avxHAX --progress / /mnt/
```
- Конфигурация `grub` для того, чтобы при старте перейти в новый `/`.
Сымитируем текущий root, сделаем в него `chroot` и обновим `grub`:
```
nazrinrus@testhost:~$ sudo su
root@testhost:/home/nazrinrus# for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done
root@testhost:/home/nazrinrus# chroot /mnt/
root@testhost:/# grub-mkconfig -o /boot/grub/grub.cfg
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-110-generic
Found initrd image: /boot/initrd.img-6.8.0-110-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
root@testhost:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-6.8.0-110-generic

root@testhost:/home/nazrinrus# reboot
```
- Просмотреть диски:
```
nazrinrus@testhost:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   40G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   38G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:1    0   19G  0 lvm  
sdb                         8:16   0   10G  0 disk 
└─vg_root-lv_root         252:0    0   10G  0 lvm  /
sdc                         8:32   0   10G  0 disk 
sdd                         8:48   0   10G  0 disk 
sde                         8:64   0   10G  0 disk 
sr0                        11:0    1 1024M  0 rom  
```
- Удалить старый LV размером в 20G и создать новый на 8G, создать файловую систему, примонтировать, скопировать данные:
```
nazrinrus@testhost:~$ sudo lvremove /dev/ubuntu-vg/ubuntu-lv
Do you really want to remove and DISCARD active logical volume ubuntu-vg/ubuntu-lv? [y/n]: y
  Logical volume "ubuntu-lv" successfully removed.
nazrinrus@testhost:~$ sudo lvcreate -n ubuntu-vg/ubuntu-lv -L 8G /dev/ubuntu-vg
WARNING: ext4 signature detected on /dev/ubuntu-vg/ubuntu-lv at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/ubuntu-vg/ubuntu-lv.
  Logical volume "ubuntu-lv" created.

sudo mkfs.ext4 /dev/ubuntu-vg/ubuntu-lv
sudo mount /dev/ubuntu-vg/ubuntu-lv /mnt
sudo rsync -avxHAX --progress / /mnt/
```
- Конфигурация grub:
```
nazrinrus@testhost:~$ sudo su
root@testhost:/home/nazrinrus# for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done
root@testhost:/home/nazrinrus# chroot /mnt/
root@testhost:/# grub-mkconfig -o /boot/grub/grub.cfg
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-110-generic
Found initrd image: /boot/initrd.img-6.8.0-110-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
root@testhost:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-6.8.0-110-generic
W: Couldn't identify type of root file system for fsck hook
```
- Пока не перезагружаемся и не выходим из под `chroot` - мы можем заодно перенести `/var`.

2. Выделить том под `/var` - сделать в mirror.
- Создать зеркало на свободных дисках:
```
root@testhost:/# pvcreate /dev/sdc /dev/sdd
  Physical volume "/dev/sdc" successfully created.
  Physical volume "/dev/sdd" successfully created.
root@testhost:/# vgcreate vg_var /dev/sdc /dev/sdd
  Volume group "vg_var" successfully created
root@testhost:/# lvcreate -L 950M -m1 -n lv_var vg_var
  Rounding up size to full physical extent 952.00 MiB
  Logical volume "lv_var" created.
```
- Создать файловую систему и переместить туда `/var`:
```
mkfs.ext4 /dev/vg_var/lv_var
mount /dev/vg_var/lv_var /mnt
cp -aR /var/* /mnt/
```
- Монтировать новый LV в `/var`:
```
root@testhost:/# mkdir /tmp/oldvar && mv /var/* /tmp/oldvar
root@testhost:/# umount /mnt
root@testhost:/# mount /dev/vg_var/lv_var /var
root@testhost:/# echo "`blkid | grep var: | awk '{print $2}'` /var ext4 defaults 0 0" >> /etc/fstab
root@testhost:/home/nazrinrus# reboot
```
- Удалить временную vg:
```
nazrinrus@testhost:~$ sudo lvremove /dev/vg_root/lv_root
Do you really want to remove and DISCARD active logical volume vg_root/lv_root? [y/n]: y
  Logical volume "lv_root" successfully removed.
nazrinrus@testhost:~$ sudo vgremove /dev/vg_root
  Volume group "vg_root" successfully removed
nazrinrus@testhost:~$ sudo pvremove /dev/sdb
  Labels on physical volume "/dev/sdb" successfully wiped.
```
3. Выделить том под `/home`.
```
sudo lvcreate -n LogVol_Home -L 2G /dev/ubuntu-vg
sudo mkfs.ext4 /dev/ubuntu-vg/LogVol_Home
sudo mount /dev/ubuntu-vg/LogVol_Home /mnt/
sudo cp -aR /home/* /mnt/
sudo rm -rf /home/*
sudo umount /mnt
sudo mount /dev/ubuntu-vg/LogVol_Home /home/
echo "`blkid | grep Home | awk '{print $2}'` /home xfs defaults 0 0" >> /etc/fstab
```
- вывод:
```
nazrinrus@testhost:~$ lsblk
NAME                       MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                          8:0    0   40G  0 disk 
├─sda1                       8:1    0    1M  0 part 
├─sda2                       8:2    0    2G  0 part /boot
└─sda3                       8:3    0   38G  0 part 
  ├─ubuntu--vg-LogVol_Home 252:0    0    2G  0 lvm  /home
  └─ubuntu--vg-ubuntu--lv  252:6    0    8G  0 lvm  /
sdb                          8:16   0   10G  0 disk 
sdc                          8:32   0   10G  0 disk 
├─vg_var-lv_var_rmeta_0    252:1    0    4M  0 lvm  
│ └─vg_var-lv_var          252:5    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_0   252:2    0  952M  0 lvm  
  └─vg_var-lv_var          252:5    0  952M  0 lvm  /var
sdd                          8:48   0   10G  0 disk 
├─vg_var-lv_var_rmeta_1    252:3    0    4M  0 lvm  
│ └─vg_var-lv_var          252:5    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_1   252:4    0  952M  0 lvm  
  └─vg_var-lv_var          252:5    0  952M  0 lvm  /var
sde                          8:64   0   10G  0 disk 
sr0                         11:0    1 1024M  0 rom  
```
4. Работа со снапшотами:
- Генерация файлов на `/home`
```
sudo touch /home/file{1..20}
```
- Снять снапшот
```
nazrinrus@testhost:~$ sudo lvcreate -L 100MB -s -n home_snap /dev/ubuntu-vg/LogVol_Home
  Logical volume "home_snap" created.
```
- Удалить часть файлов
```
sudo rm -f /home/file{11..20}
```
- Восстановление из снапшота
```
umount /home
lvconvert --merge /dev/ubuntu-vg/home_snap
mount /dev/mapper/ubuntu--vg-LogVol_Home /home
```
Восстановление из снапшота было поставлено в очередь, т.к. `/home` использовалось системой. После перезагрузки произошло восстановление из снапшота.
