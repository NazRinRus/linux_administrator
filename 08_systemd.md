### Systemd - создание unit-файла
#### Цель:
Научиться редактировать существующие и создавать новые unit-файлы;

#### Задачи:
1. Написать `service`, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в `/etc/default`).
2. Установить `spawn-fcgi` и создать unit-файл (`spawn-fcgi.sevice`) с помощью переделки init-скрипта (https://gist.github.com/cea2k/1318020).
3. Доработать unit-файл Nginx (`nginx.service`) для запуска нескольких инстансов сервера с разными конфигурационными файлами одновременно.

#### Реализация:
1. Написать `service` для экспортера метрик, который будет раз в 30 секунд мониторить лог на предмет наличия ключевого слова (файл лога и ключевое слово должны задаваться в `/etc/default`), транслировать полученную метрику в формате prometheus на порту `9878`.
- Создать файл конфигурации сервиса - `sudo vim /etc/default/pg_log_exporter.conf`:
```
WORD="ERROR"
LOG_FILE=/var/log/postgresql/postgresql-17-main.log
```
- Скрипт проверки лога `vim /opt/scripts/reports/pg_log_exporter.sh`:
```
#!/bin/bash

WORD=$2
LOG_FILE=$3
METRIC_NAME="postgresql_errors_total"
PORT=9878
HOST="127.0.0.1"

count_errors() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "0"
        return
    fi
    
    grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0"
}

generate_metrics() {
    local errors_total=$(count_errors)
    local timestamp=$(date +%s)
    
    cat <<EOF
# HELP $METRIC_NAME Total number of ERROR lines in PostgreSQL log
# TYPE $METRIC_NAME counter
${METRIC_NAME}_total ${errors_total} ${timestamp}
EOF
}

run_http_server() {
    echo "Starting Prometheus metrics exporter on ${HOST}:${PORT}"
    echo "Metrics path: /metrics"
    
    while true; do
        if command -v nc &> /dev/null; then
            echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n$(generate_metrics)" | nc -l -p $PORT -s $HOST -q 1
        elif command -v socat &> /dev/null; then
            echo "$(generate_metrics)" | socat TCP-LISTEN:$PORT,fork,reuseaddr,bind=$HOST TCP-CONNECT:localhost:9879 2>/dev/null || {
                echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$(generate_metrics)" | socat - TCP-LISTEN:$PORT,fork,reuseaddr,bind=$HOST
            }
        else
            while true; do
                (echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$(generate_metrics)") | nc -l -p $PORT -s $HOST -q 1
            done
        fi
        sleep 1
    done
}

case "${1:-serve}" in
    serve)
        run_http_server
        ;;
    count)
        echo "Total errors: $(count_errors)"
        ;;
    help|--help|-h)
        echo "Usage: $0 [serve|print|count]"
        echo "  serve - Run HTTP server on port $PORT (default)"
        echo "  print - Print metrics once and exit"
        echo "  count - Show total error count only"
        ;;
    *)
        echo "Unknown command: $1"
        exit 1
        ;;
esac
```
`chmod +x /opt/scripts/reports/pg_log_exporter.sh`
- Создать unit-файл `sudo vim /etc/systemd/system/pg_log_exporter.service`:
```
[Unit]
Description=PostgreSQL Log Prometheus Exporter
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
EnvironmentFile=/etc/default/pg_log_exporter.conf
ExecStart=/opt/scripts/reports/pg_log_exporter.sh serve $WORD $LOG_FILE
Restart=always
RestartSec=30

PrivateTmp=true
NoNewPrivileges=false

StandardOutput=journal
StandardError=journal
SyslogIdentifier=pg_log_exporter

[Install]
WantedBy=multi-user.target
```
- `sudo systemctl daemon-reload`
- `sudo systemctl enable pg_log_exporter`
- `sudo systemctl start pg_log_exporter`
- `sudo systemctl status pg_log_exporter`:
```
● pg_log_exporter.service - PostgreSQL Log Prometheus Exporter
     Loaded: loaded (/etc/systemd/system/pg_log_exporter.service; enabled; preset: enabled)
     Active: active (running) since Tue 2026-05-05 16:46:08 UTC; 1min 54s ago
   Main PID: 3071 (pg_log_exporter)
      Tasks: 2 (limit: 4601)
     Memory: 632.0K (peak: 1.9M)
        CPU: 17ms
     CGroup: /system.slice/pg_log_exporter.service
             ├─3071 /bin/bash /opt/scripts/reports/pg_log_exporter.sh serve ERROR /var/log/postgresql/postgresql-17-main.log
             └─3092 nc -l -p 9878 -s 127.0.0.1 -q 1

мая 05 16:46:08 test-host systemd[1]: Started pg_log_exporter.service - PostgreSQL Log Prometheus Exporter.
мая 05 16:46:08 test-host pg_log_exporter[3071]: Starting Prometheus metrics exporter on 127.0.0.1:9878
мая 05 16:46:08 test-host pg_log_exporter[3071]: Metrics path: /metrics
```
- Текущее количество ошибок в логе:
```
curl http://127.0.0.1:9878/metrics
# HELP postgresql_errors_total Total number of ERROR lines in PostgreSQL log
# TYPE postgresql_errors_total counter
postgresql_errors_total_total 1 1777999568
```
- Искусственно сгенерировал ошибку:
```
(for_databases) nazrinrus@test-host:~$ sudo -u postgres psql -d demo -c 'SELECT 1/0;'
ERROR:  division by zero
```
- Получаю метрику после ошибки:
```
(for_databases) nazrinrus@test-host:~$ curl http://127.0.0.1:9878/metrics
# HELP postgresql_errors_total Total number of ERROR lines in PostgreSQL log
# TYPE postgresql_errors_total counter
postgresql_errors_total_total 2 1777999923
```
- Проверяю лог вручную:
```
(for_databases) nazrinrus@test-host:~$ tail -n 10 /var/log/postgresql/postgresql-17-main.log
2026-05-05 14:13:08.815 UTC [855] LOG:  listening on IPv6 address "::", port 5432
2026-05-05 14:13:08.836 UTC [855] LOG:  listening on Unix socket "/var/run/postgresql/.s.PGSQL.5432"
2026-05-05 14:13:08.879 UTC [910] LOG:  database system was shut down at 2026-04-25 08:19:08 UTC
2026-05-05 14:13:08.911 UTC [855] LOG:  database system is ready to accept connections
2026-05-05 14:18:11.675 UTC [908] LOG:  checkpoint starting: time
2026-05-05 14:18:11.691 UTC [908] LOG:  checkpoint complete: wrote 3 buffers (0.0%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.007 s, sync=0.002 s, total=0.017 s; sync files=2, longest=0.001 s, average=0.001 s; distance=0 kB, estimate=0 kB; lsn=0/47ED75D0, redo lsn=0/47ED7578
2026-05-05 15:30:32.872 UTC [2169] postgres@demo ERROR:  division by zero
2026-05-05 15:30:32.872 UTC [2169] postgres@demo STATEMENT:  SELECT 1/0;
2026-05-05 16:50:06.419 UTC [3376] postgres@demo ERROR:  division by zero
2026-05-05 16:50:06.419 UTC [3376] postgres@demo STATEMENT:  SELECT 1/0;
```
2. Установить `spawn-fcgi` и создать unit-файл (`spawn-fcgi.sevice`) с помощью переделки init-скрипта (https://gist.github.com/cea2k/1318020).
- Установка `sudo apt install spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid -y`:
- Создать файл с настройками: `sudo vim /etc/spawn-fcgi/fcgi.conf`:
```
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s $SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
```
- Создать unit-файл `sudo vim /etc/systemd/system/spawn-fcgi.service`:
```
[Unit]
Description=Spawn-fcgi startup service by Otus
After=network.target

[Service]
Type=simple
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/spawn-fcgi/fcgi.conf
ExecStart=/usr/bin/spawn-fcgi -n $OPTIONS
KillMode=process

[Install]
WantedBy=multi-user.target
```
- Проверка:
```
(for_databases) nazrinrus@test-host:~$ systemctl start spawn-fcgi
==== AUTHENTICATING FOR org.freedesktop.systemd1.manage-units ====
Authentication is required to start 'spawn-fcgi.service'.
Authenticating as: nazrinrus
Password: 
==== AUTHENTICATION COMPLETE ====
(for_databases) nazrinrus@test-host:~$ systemctl status spawn-fcgi
● spawn-fcgi.service - Spawn-fcgi startup service by Otus
     Loaded: loaded (/etc/systemd/system/spawn-fcgi.service; disabled; preset: enabled)
     Active: active (running) since Tue 2026-05-05 17:37:33 UTC; 12s ago
   Main PID: 12590 (php-cgi)
      Tasks: 33 (limit: 4601)
     Memory: 14.6M (peak: 15.0M)
        CPU: 30ms
     CGroup: /system.slice/spawn-fcgi.service
             ├─12590 /usr/bin/php-cgi
             ├─12591 /usr/bin/php-cgi
             ├─12592 /usr/bin/php-cgi
             ├─12593 /usr/bin/php-cgi
             ├─12594 /usr/bin/php-cgi
             ├─12595 /usr/bin/php-cgi
             ├─12596 /usr/bin/php-cgi
             ├─12597 /usr/bin/php-cgi
● spawn-fcgi.service - Spawn-fcgi startup service by Otus
     Loaded: loaded (/etc/systemd/system/spawn-fcgi.service; disabled; preset: enabled)
     Active: active (running) since Tue 2026-05-05 17:37:33 UTC; 12s ago
   Main PID: 12590 (php-cgi)
      Tasks: 33 (limit: 4601)
     Memory: 14.6M (peak: 15.0M)
        CPU: 30ms
     CGroup: /system.slice/spawn-fcgi.service
             ├─12590 /usr/bin/php-cgi
             ├─12591 /usr/bin/php-cgi
             ├─12592 /usr/bin/php-cgi
             ├─12593 /usr/bin/php-cgi
             ├─12594 /usr/bin/php-cgi
             ├─12595 /usr/bin/php-cgi
             ├─12596 /usr/bin/php-cgi
             ├─12597 /usr/bin/php-cgi
             ├─12598 /usr/bin/php-cgi
             ├─12599 /usr/bin/php-cgi
             ├─12600 /usr/bin/php-cgi
             ├─12601 /usr/bin/php-cgi
             ├─12602 /usr/bin/php-cgi
             ├─12603 /usr/bin/php-cgi
             ├─12604 /usr/bin/php-cgi
             ├─12605 /usr/bin/php-cgi
             ├─12606 /usr/bin/php-cgi
             ├─12607 /usr/bin/php-cgi
             ├─12608 /usr/bin/php-cgi
             ├─12609 /usr/bin/php-cgi
             ├─12610 /usr/bin/php-cgi
             ├─12611 /usr/bin/php-cgi
             ├─12612 /usr/bin/php-cgi
             ├─12613 /usr/bin/php-cgi
             ├─12614 /usr/bin/php-cgi
             ├─12615 /usr/bin/php-cgi
             ├─12616 /usr/bin/php-cgi
             ├─12617 /usr/bin/php-cgi
             ├─12618 /usr/bin/php-cgi
             ├─12619 /usr/bin/php-cgi
             ├─12620 /usr/bin/php-cgi
             ├─12621 /usr/bin/php-cgi
             └─12622 /usr/bin/php-cgi

мая 05 17:37:33 test-host systemd[1]: Started spawn-fcgi.service - Spawn-fcgi startup service by Otus.
```
3. Доработать unit-файл Nginx (`nginx.service`) для запуска нескольких инстансов сервера с разными конфигурационными файлами одновременно:
Для запуска нескольких экземпляров Nginx на одном сервере лучше всего использовать шаблонный unit-файл (nginx@.service).
- Установка: `sudo apt install nginx -y`
- Создать unit-файл для шаблона - `sudo vim /etc/systemd/system/nginx@.service`: 
```
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx-%I.pid
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx-%I.conf -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx-%I.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
```
- Создать два конфигурационных файла, на основе существующего:
```
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx-first.conf
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx-second.conf
```
- Прописать в конфиги:
```
pid /run/nginx-first.pid;

http {
…
	server {
		listen 9001;
	}
#include /etc/nginx/sites-enabled/*;
```
```
pid /run/nginx-second.pid;

http {
…
	server {
		listen 9002;
	}
#include /etc/nginx/sites-enabled/*;
```
- Запуск сервисов:
```
sudo systemctl start nginx@second
sudo systemctl start nginx@first
```
- Проверка:
```
(for_databases) nazrinrus@test-host:~$ ps afx | grep nginx
  13381 pts/0    S+     0:00              \_ grep --color=auto nginx
  13328 ?        Ss     0:00 nginx: master process /usr/sbin/nginx -c /etc/nginx/nginx-first.conf -g daemon on; master_process on;
  13329 ?        S      0:00  \_ nginx: worker process
  13330 ?        S      0:00  \_ nginx: worker process
  13353 ?        Ss     0:00 nginx: master process /usr/sbin/nginx -c /etc/nginx/nginx-second.conf -g daemon on; master_process on;
  13354 ?        S      0:00  \_ nginx: worker process
  13355 ?        S      0:00  \_ nginx: worker process
(for_databases) nazrinrus@test-host:~$ curl http://127.0.0.1:9001
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
(for_databases) nazrinrus@test-host:~$ curl http://127.0.0.1:9002
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```
