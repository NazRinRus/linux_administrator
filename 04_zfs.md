### Работа с ZFS
1. Определить алгоритм с наилучшим сжатием:
- определить, какие алгоритмы сжатия поддерживает zfs (gzip, zle, lzjb, lz4);
- создать 4 файловых системы, на каждой применить свой алгоритм сжатия;
- для сжатия использовать либо текстовый файл, либо группу файлов.
2. Определить настройки пула.
- С помощью команды zfs import собрать pool ZFS.
- Командами zfs определить настройки: (размер хранилища, тип pool, значение recordsize, какое сжатие используется, какая контрольная сумма используется)
3. Работа со снапшотами:
- скопировать файл из удаленной директории;
- восстановить файл локально. zfs receive;
- найти зашифрованное сообщение в файле secret_message

#### Инфраструктура 
```
nazrinrus@testhost:~$ lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   40G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   38G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0   19G  0 lvm  /
sdb                         8:16   0    1G  0 disk 
sdc                         8:32   0    1G  0 disk 
sdd                         8:48   0    1G  0 disk 
sde                         8:64   0    1G  0 disk 
sdf                         8:80   0    1G  0 disk 
sdg                         8:96   0    1G  0 disk 
sdh                         8:112  0    1G  0 disk 
sdi                         8:128  0    1G  0 disk 
sr0                        11:0    1 1024M  0 rom  
```
#### Установка пакетов
```
sudo apt install zfsutils-linux -y
```
#### Определить алгоритм с наилучшим сжатием
1. Поддерживаемые алгоритмы:
| Алгоритм | Производительность | Сжатие | Рекомендации |
|-------|--------|---------|--------|
| LZ4 | Отличная | Средняя  | Баланс между скоростью и сжатием. Можно использовать по умолчанию |
| ZLE | Очень высокая | Очень низкая | Полезен для виртуальных дисков или дампов памяти, где много неиспользуемого пространства, заполненного нулями |
| GZIP | Низкая. Варьируется от степени сжатия | Высокая. Варьируется от gzip-1 до gzip-9 | Для архивных данных, где важна экономия места, а не скорость |
| LZJB | LZ4 превосходит его по всем показателям | Низкая или средняя | Оставлен для совместимости |

2. Создать 4 файловых системы, на каждой применить свой алгоритм сжатия:
```
sudo zpool create pool_lz4 mirror /dev/sdb /dev/sdc
sudo zpool create pool_zle mirror /dev/sdd /dev/sde
sudo zpool create pool_gzip mirror /dev/sdf /dev/sdg
sudo zpool create pool_lzjb mirror /dev/sdh /dev/sdi
zpool list
NAME        SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
pool_gzip   960M   129K   960M        -         -     0%     0%  1.00x    ONLINE  -
pool_lz4    960M   104K   960M        -         -     0%     0%  1.00x    ONLINE  -
pool_lzjb   960M   134K   960M        -         -     0%     0%  1.00x    ONLINE  -
pool_zle    960M   114K   960M        -         -     0%     0%  1.00x    ONLINE  -
```
- Применить алгоритм сжатия:
```
sudo zfs set compression=gzip-9 pool_gzip
sudo zfs set compression=lz4 pool_lz4
sudo zfs set compression=lzjb pool_lzjb
sudo zfs set compression=zle pool_zle

zfs get all | grep compression
pool_gzip  compression           gzip-9                 local
pool_lz4   compression           lz4                    local
pool_lzjb  compression           lzjb                   local
pool_zle   compression           zle                    local
```
Сжатие файлов будет работать только с файлами, которые были добавлены после включение настройки сжатия.
3. Скачать текстовый файл во все пулы, сравнить степень сжатия:
```
for i in gzip lz4 lzjb zle; do wget -P /pool_$i https://gutenberg.org/cache/epub/2600/pg2600.converter.log; done

root@testhost:~# ls -lah /pool_*
/pool_gzip:
total 11M
drwxr-xr-x  2 root root    3 Apr 25 17:29 .
drwxr-xr-x 27 root root 4.0K Apr 25 17:12 ..
-rw-r--r--  1 root root  40M Apr  2 07:31 pg2600.converter.log

/pool_lz4:
total 18M
drwxr-xr-x  2 root root    3 Apr 25 17:29 .
drwxr-xr-x 27 root root 4.0K Apr 25 17:12 ..
-rw-r--r--  1 root root  40M Apr  2 07:31 pg2600.converter.log

/pool_lzjb:
total 22M
drwxr-xr-x  2 root root    3 Apr 25 17:29 .
drwxr-xr-x 27 root root 4.0K Apr 25 17:12 ..
-rw-r--r--  1 root root  40M Apr  2 07:31 pg2600.converter.log

/pool_zle:
total 40M
drwxr-xr-x  2 root root    3 Apr 25 17:30 .
drwxr-xr-x 27 root root 4.0K Apr 25 17:12 ..
-rw-r--r--  1 root root  40M Apr  2 07:31 pg2600.converter.log

root@testhost:~# zfs list
NAME        USED  AVAIL  REFER  MOUNTPOINT
pool_gzip  10.9M   821M  10.7M  /pool_gzip
pool_lz4   17.7M   814M  17.6M  /pool_lz4
pool_lzjb  21.8M   810M  21.6M  /pool_lzjb
pool_zle   39.5M   793M  39.4M  /pool_zle
root@testhost:~# zfs get all | grep compressratio | grep -v ref
pool_gzip  compressratio         3.66x                  -
pool_lz4   compressratio         2.23x                  -
pool_lzjb  compressratio         1.82x                  -
pool_zle   compressratio         1.00x                  -
```
Самый эффективный метод сжатия - `gzip-9`

#### Определить настройки пула
1. Скачать и разархивировать архив:
```
cd /tmp
wget -O archive.tar.gz --no-check-certificate 'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
root@testhost:/tmp# tar -xzvf archive.tar.gz
zpoolexport/
zpoolexport/filea
zpoolexport/fileb
```
2. Проверить возможно ли имортировать каталог в пул:
```
root@testhost:/tmp# zpool import -d zpoolexport/
   pool: otus
     id: 6554193320433390805
  state: ONLINE
status: Some supported features are not enabled on the pool.
        (Note that they may be intentionally disabled if the
        'compatibility' property is set.)
 action: The pool can be imported using its name or numeric identifier, though
        some features will not be available without an explicit 'zpool upgrade'.
 config:

        otus                        ONLINE
          mirror-0                  ONLINE
            /tmp/zpoolexport/filea  ONLINE
            /tmp/zpoolexport/fileb  ONLINE
```
3. Импортировать пул в ОС:
```
root@testhost:/tmp# zpool import -d zpoolexport/ otus
root@testhost:/tmp# zpool status
  pool: otus
 state: ONLINE
status: Some supported and requested features are not enabled on the pool.
        The pool can still be used, but some features are unavailable.
action: Enable all features using 'zpool upgrade'. Once this is done,
        the pool may no longer be accessible by software that does not support
        the features. See zpool-features(7) for details.
config:

        NAME                        STATE     READ WRITE CKSUM
        otus                        ONLINE       0     0     0
          mirror-0                  ONLINE       0     0     0
            /tmp/zpoolexport/filea  ONLINE       0     0     0
            /tmp/zpoolexport/fileb  ONLINE       0     0     0

errors: No known data errors
...
```
4. Определить настройки. Команды `zpool get all otus` или `zfs get all otus` выводят полный список настроек, желательно грепнуть его для вывода конкретной или указать имя параметра:
- Размер
```
root@testhost:/tmp# zfs get available otus
NAME  PROPERTY   VALUE  SOURCE
otus  available  350M   -
```
- Тип
```
root@testhost:/tmp# zfs get readonly otus
NAME  PROPERTY  VALUE   SOURCE
otus  readonly  off     default
```
- Значение recordsize
```
root@testhost:/tmp# zfs get recordsize otus
NAME  PROPERTY    VALUE    SOURCE
otus  recordsize  128K     local
```
- Тип сжатия
```
root@testhost:/tmp# zfs get compression otus
NAME  PROPERTY     VALUE           SOURCE
otus  compression  zle             local
```
- Тип контрольной суммы
```
root@testhost:/tmp# zfs get checksum otus
NAME  PROPERTY  VALUE      SOURCE
otus  checksum  sha256     local
```
#### Работа со снапшотами
1. Скачать файл снапшота:
```
wget -O otus_task2.file --no-check-certificate https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download
```
2. Восстановить файловую систему из снапшота:
```
zfs receive otus/test@today < otus_task2.file
```
3. Найти в директории `/otus/test` файл с именем `secret_message`:
```
root@pg-node1:/tmp# find /otus/test -name "secret_message"
/otus/test/task1/file_mess/secret_message

cat /otus/test/task1/file_mess/secret_message
https://otus.ru/lessons/linux-hl/
```
