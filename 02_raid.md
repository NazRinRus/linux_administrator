### RAID-массивы
#### Заметки по теории
В RAID-массив можно объединять как диски, так и разделы.

1. `RAID 0` - Ускорение записи и чтения. Данные, в одном экземпляре, распределяются между дисками массива. Два диска по 1 ТБ дают общее пространство в 2 ТБ. При выводе из строя одного из диска, данные будут утеряны;
2. `RAID 1` - Репликация данных (Ускоряется только чтение). Данные пишутся в двух экземплярах, диски дублируют друг друга. Два диска по 1 ТБ дают общее пространство в 1 ТБ. Без последствий могут упасть любое количество дисков, остаться должен хотябы 1 диск;
3. `RAID 10` - компромисс между `RAID 0` и `RAID 1`. Минимум 4 диска. По сути это репликация `RAID 0` - данные распределяются между двумя дисками и каждый из них реплицируется. Без последствий может выйти из строя любой из дисков или два диска но из разных реплик. Четыре диска по 1 ТБ дают общее пространство в 2 ТБ.

`mdadm` - утилита для работы с программными RAID-массивами в Линукс.

#### Создать RAID 10 
К виртуальной машине подключены 4 виртуальных диска по 20ГБ. Требуется создать программный RAID-массив `RAID 10` при помощи утилиты `mdadm`.
```
nazrinrus@pg-node1:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   10G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0  1.8G  0 part /boot
└─sda3                      8:3    0  8.2G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0  8.2G  0 lvm  /
sdb                         8:16   0   20G  0 disk 
sdc                         8:32   0   20G  0 disk 
sdd                         8:48   0   20G  0 disk 
sde                         8:64   0   20G  0 disk 
sr0                        11:0    1 1024M  0 rom  
```
1. Очистка старых RAID-метаданных. На случай, если диски ранее использовались в других RAID-массивах:
```
nazrinrus@pg-node1:~$ sudo mdadm --zero-superblock /dev/sdb /dev/sdc /dev/sdd /dev/sde
mdadm: Unrecognised md component device - /dev/sdb
mdadm: Unrecognised md component device - /dev/sdc
mdadm: Unrecognised md component device - /dev/sdd
mdadm: Unrecognised md component device - /dev/sde
```
2. Создание массива типа `RAID 10`:
```
nazrinrus@pg-node1:~$ sudo mdadm --create /dev/md0 --level=10 --raid-devices=4 /dev/sdb /dev/sdc /dev/sdd /dev/sde
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.
```
- `--level=10` или `-l` - тип RAID
- `--raid-devices=4` или `-n` - количество дисков
- Полезный объём массива будет 40 ГБ (20 ГБ × 4 / 2)

3. Проверка состояния и фоновой синхронизации:
```
nazrinrus@pg-node1:~$ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid10 sde[3] sdd[2] sdc[1] sdb[0]
      41908224 blocks super 1.2 512K chunks 2 near-copies [4/4] [UUUU]
      [=>...................]  resync =  8.1% (3426432/41908224) finish=13.1min speed=48629K/sec


```
- `resync =  8.1%` - происходит синхронизация данных между дисками. Процесс продолжительный, т.к. виртуальные диски на старом физическом HDD 
- `[4/4] [UUUU]` - из 4 дисков 4 в строю и все в состоянии `Up`
```
nazrinrus@pg-node1:~$ sudo mdadm --detail /dev/md0
/dev/md0:
           Version : 1.2
     Creation Time : Sun Apr 12 13:04:48 2026
        Raid Level : raid10
        Array Size : 41908224 (39.97 GiB 42.91 GB)
     Used Dev Size : 20954112 (19.98 GiB 21.46 GB)
      Raid Devices : 4
     Total Devices : 4
       Persistence : Superblock is persistent

       Update Time : Sun Apr 12 13:08:24 2026
             State : clean, resyncing 
    Active Devices : 4
   Working Devices : 4
    Failed Devices : 0
     Spare Devices : 0

            Layout : near=2
        Chunk Size : 512K

Consistency Policy : resync

     Resync Status : 25% complete

              Name : pg-node1:0  (local to host pg-node1)
              UUID : 260382fc:aa56cdc4:c61b4410:659a8b97
            Events : 4

    Number   Major   Minor   RaidDevice State
       0       8       16        0      active sync set-A   /dev/sdb
       1       8       32        1      active sync set-B   /dev/sdc
       2       8       48        2      active sync set-A   /dev/sdd
       3       8       64        3      active sync set-B   /dev/sde
```
После синхронизации:
```
nazrinrus@pg-node1:~$ sudo mdadm --detail /dev/md0
/dev/md0:
           Version : 1.2
     Creation Time : Sun Apr 12 13:04:48 2026
        Raid Level : raid10
        Array Size : 41908224 (39.97 GiB 42.91 GB)
     Used Dev Size : 20954112 (19.98 GiB 21.46 GB)
      Raid Devices : 4
     Total Devices : 4
       Persistence : Superblock is persistent

       Update Time : Sun Apr 12 13:19:01 2026
             State : clean 
    Active Devices : 4
   Working Devices : 4
    Failed Devices : 0
     Spare Devices : 0

            Layout : near=2
        Chunk Size : 512K

Consistency Policy : resync

              Name : pg-node1:0  (local to host pg-node1)
              UUID : 260382fc:aa56cdc4:c61b4410:659a8b97
            Events : 17

    Number   Major   Minor   RaidDevice State
       0       8       16        0      active sync set-A   /dev/sdb
       1       8       32        1      active sync set-B   /dev/sdc
       2       8       48        2      active sync set-A   /dev/sdd
       3       8       64        3      active sync set-B   /dev/sde
nazrinrus@pg-node1:~$ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid10 sde[3] sdd[2] sdc[1] sdb[0]
      41908224 blocks super 1.2 512K chunks 2 near-copies [4/4] [UUUU]
      
unused devices: <none>
```
как выглядит:
```
nazrinrus@pg-node1:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE   MOUNTPOINTS
sda                         8:0    0   10G  0 disk   
├─sda1                      8:1    0    1M  0 part   
├─sda2                      8:2    0  1.8G  0 part   /boot
└─sda3                      8:3    0  8.2G  0 part   
  └─ubuntu--vg-ubuntu--lv 252:0    0  8.2G  0 lvm    /
sdb                         8:16   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
sdc                         8:32   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
sdd                         8:48   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
sde                         8:64   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
sr0                        11:0    1 1024M  0 rom    
```
#### Сломайть и починить RAID
Имитировать поломку можно:
- отключив виртуальный диск от виртуальной машины;
- искусственно “зафейлив” одно из блочных устройств командной:
```
mdadm /dev/md0 --fail /dev/sde
```
1. Для практики выбираем искуственный выход из строя:
```
nazrinrus@pg-node1:~$ sudo mdadm /dev/md0 --fail /dev/sde
mdadm: set /dev/sde faulty in /dev/md0

nazrinrus@pg-node1:~$ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid10 sde[3](F) sdd[2] sdc[1] sdb[0]
      41908224 blocks super 1.2 512K chunks 2 near-copies [4/3] [UUU_]
      
unused devices: <none>
```
видно, что 3 из 4 дисков в статусе `Up`

2. Удалить сломанный диск из массива:
```
nazrinrus@pg-node1:~$ sudo mdadm /dev/md0 --remove /dev/sde
mdadm: hot removed /dev/sde from /dev/md0
```
3. Физически удалили сломанный диск, добавили новый, теперь добавим его в массив:
```
nazrinrus@pg-node1:~$ sudo mdadm /dev/md0 --add /dev/sde
mdadm: added /dev/sde

nazrinrus@pg-node1:~$ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid10 sde[4] sdd[2] sdc[1] sdb[0]
      41908224 blocks super 1.2 512K chunks 2 near-copies [4/3] [UUU_]
      [=>...................]  recovery =  6.3% (1323840/20954112) finish=6.6min speed=49031K/sec
      
unused devices: <none>
```
- `recovery =  6.3%` - новый диск проходит стадию `rebuilding`

#### Создать GPT таблицу, пять разделов и смонтировать их в системе
1. Создать раздел GPT на RAID:
```
nazrinrus@pg-node1:~$ sudo parted -s /dev/md0 mklabel gpt
```
2. Создать пользовательские разделы:
```
nazrinrus@pg-node1:~$ sudo parted /dev/md0 mkpart primary ext4 0% 20%
Information: You may need to update /etc/fstab.

nazrinrus@pg-node1:~$ sudo parted /dev/md0 mkpart primary ext4 20% 40%    
Information: You may need to update /etc/fstab.

nazrinrus@pg-node1:~$ sudo parted /dev/md0 mkpart primary ext4 40% 60%    
Information: You may need to update /etc/fstab.

nazrinrus@pg-node1:~$ sudo parted /dev/md0 mkpart primary ext4 60% 80%    
Information: You may need to update /etc/fstab.

nazrinrus@pg-node1:~$ sudo parted /dev/md0 mkpart primary ext4 80% 100%   
Information: You may need to update /etc/fstab.
```
3. Создать файловую систему:
```
nazrinrus@pg-node1:~$ for i in $(seq 1 5); do sudo mkfs.ext4 /dev/md0p$i; done
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2095104 4k blocks and 524288 inodes
Filesystem UUID: f5cd7fb7-e9c3-4fda-b385-5f8c5149645a
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2095360 4k blocks and 524288 inodes
Filesystem UUID: cf87fcaa-2202-4df0-8631-24766541b459
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2095616 4k blocks and 524288 inodes
Filesystem UUID: 2151afe6-37ae-45f1-a65f-f936a8c4ec68
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2095360 4k blocks and 524288 inodes
Filesystem UUID: 8b6d2c50-0052-45ae-b01f-1e78ce1b739b
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2095104 4k blocks and 524288 inodes
Filesystem UUID: 5888e43e-6445-4abf-b76c-092369f5799c
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done                            
Writing inode tables: done                            
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done
```
4. Монтирование в каталоги:
```
nazrinrus@pg-node1:~$ sudo mkdir -p /raid/part{1,2,3,4,5}

nazrinrus@pg-node1:~$ for i in $(seq 1 5); do sudo mount /dev/md0p$i /raid/part$i; done
nazrinrus@pg-node1:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE   MOUNTPOINTS
sda                         8:0    0   10G  0 disk   
├─sda1                      8:1    0    1M  0 part   
├─sda2                      8:2    0  1.8G  0 part   /boot
└─sda3                      8:3    0  8.2G  0 part   
  └─ubuntu--vg-ubuntu--lv 252:0    0  8.2G  0 lvm    /
sdb                         8:16   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
  ├─md0p1                 259:0    0    8G  0 part   /raid/part1
  ├─md0p2                 259:1    0    8G  0 part   /raid/part2
  ├─md0p3                 259:2    0    8G  0 part   /raid/part3
  ├─md0p4                 259:3    0    8G  0 part   /raid/part4
  └─md0p5                 259:4    0    8G  0 part   /raid/part5
sdc                         8:32   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
  ├─md0p1                 259:0    0    8G  0 part   /raid/part1
  ├─md0p2                 259:1    0    8G  0 part   /raid/part2
  ├─md0p3                 259:2    0    8G  0 part   /raid/part3
  ├─md0p4                 259:3    0    8G  0 part   /raid/part4
  └─md0p5                 259:4    0    8G  0 part   /raid/part5
sdd                         8:48   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
  ├─md0p1                 259:0    0    8G  0 part   /raid/part1
  ├─md0p2                 259:1    0    8G  0 part   /raid/part2
  ├─md0p3                 259:2    0    8G  0 part   /raid/part3
  ├─md0p4                 259:3    0    8G  0 part   /raid/part4
  └─md0p5                 259:4    0    8G  0 part   /raid/part5
sde                         8:64   0   20G  0 disk   
└─md0                       9:0    0   40G  0 raid10 
  ├─md0p1                 259:0    0    8G  0 part   /raid/part1
  ├─md0p2                 259:1    0    8G  0 part   /raid/part2
  ├─md0p3                 259:2    0    8G  0 part   /raid/part3
  ├─md0p4                 259:3    0    8G  0 part   /raid/part4
  └─md0p5                 259:4    0    8G  0 part   /raid/part5
sr0                        11:0    1 1024M  0 rom    
nazrinrus@pg-node1:~$ df -h
Filesystem                         Size  Used Avail Use% Mounted on
tmpfs                              197M  1.2M  196M   1% /run
/dev/mapper/ubuntu--vg-ubuntu--lv  8.1G  4.4G  3.3G  58% /
tmpfs                              985M     0  985M   0% /dev/shm
tmpfs                              5.0M     0  5.0M   0% /run/lock
/dev/sda2                          1.7G  196M  1.4G  13% /boot
tmpfs                              197M   12K  197M   1% /run/user/1000
/dev/md0p1                         7.8G   24K  7.4G   1% /raid/part1
/dev/md0p2                         7.8G   24K  7.4G   1% /raid/part2
/dev/md0p3                         7.8G   24K  7.4G   1% /raid/part3
/dev/md0p4                         7.8G   24K  7.4G   1% /raid/part4
/dev/md0p5                         7.8G   24K  7.4G   1% /raid/part5
```
