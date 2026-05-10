## Практика. Работа с bash скриптами
### Задача
Написать скрипт для CRON, который раз в час формирует отчёт и отправляет его на заданную почту.

Отчёт должен содержать:
- IP-адреса с наибольшим числом запросов (с момента последнего запуска);
- Запрашиваемые URL с наибольшим числом запросов (с момента последнего запуска);
- Ошибки веб-сервера/приложения (с момента последнего запуска);
- HTTP-коды ответов с указанием их количества (с момента последнего запуска).
- Скрипт должен предотвращать одновременный запуск нескольких копий, до его завершения.
- В письме должен быть прописан обрабатываемый временной диапазон.

### Решение
#### Скелет скрипта:
1. При запуске, скрипт считывает конфигурационные параметры по умолчанию, в которых содержаться путь к файлу-источнику и список адресов - получателей отчета;
2. Возможность передачи параметров скрипту. Параметры не позиционные, а именнованные. Значения, переданные параметрами имеют приоритет перед значениями конфигурации по умолчанию;
3. Проверка существования уже запущенного ранее экземпляра скрипта.
#### Логика работы с файлами:
1. Временная метка лог-файла, на которой скрипт остановился в прошлый раз, записывается в файл `.previous_iteration`. Метка в виде номера строки. При ротации проверяемого лог-файла, следует удалить или очистить файл `.previous_iteration`, иначе поиск будет осуществляться не с начала файла;
2. Скрипт пишет результат проверки в файл `ws_reports/начальная_метка-конечная_метка`, содержимое которого будет отправлять по почте;
#### Логика поиска:
1. Циклом от начальной позиции до последней позиции, будут перебираться строки. Из каждой строки будут скопированы искомые значения, помещены в ассоциативный массив со счетчиком, каждый раз как значение будет повторяться, счетчик будет прибавляться. При отсутствии значения, будет добавляться элемент массива со значением 1. 


#### Реализация
#### Скелет скрипта:
1. Рабочая директория: `sudo mkdir -p /opt/scripts/web_server_reports/ws_reports && cd /opt/scripts/web_server_reports`;
2. Файл скрипта: `sudo touch web_server_reports.sh && sudo chmod +x web_server_reports.sh`;
3. Проверка на существование раннее запущенного экземпляра скрипта:
- `sudo vim web_server_reports.sh`
```
#!/bin/bash

LOCK_FILE="/var/run/$(basename "$0").lock"

exec 200>"$LOCK_FILE"

if ! flock -n 200; then
    echo "Уже запущен экземпляр данного скрипта"
    exit 1
fi

echo "Запущен скрипт - PID $$"
```
4. Конфигурация по умолчанию:
```
DEFAULT_SOURCE_FILE="/opt/scripts/web_server_reports/access.log"
DEFAULT_LOG_FILE="/tmp/ws_report.log"
DEFAULT_ITER_FILE="/opt/scripts/web_server_reports/.previous_iteration"
DEFAULT_RECIPIENTS_LIST="nazrinrus@gmail.com"
```
5. Парсинг переданных скрипту параметров:
```
while [ $# -gt 0 ]; do
    case "${1}" in
        --source_file|-s)
            SOURCE_FILE="${2}"
            shift
	    ;;
        --log_file|-l)
            LOG_FILE="${2}"
            shift
	    ;;
	    --recipients_list|-r)
            RECIPIENTS_LIST="${2}"
            shift
	    ;;
        --iter_file|-r)
            ITER_FILE="${2}"
            shift
	    ;;
    esac
    shift || true
done
```
- пример команды: `sudo ./web_server_reports.sh --source_file /opt/scripts/web_server_reports/access.log --recipients_list example@mail.ru`

6. Инициализация констант, значениями, переданными параметрами или из конфигурации по умолчанию:
```
SOURCE_FILE="${SOURCE_FILE:-$DEFAULT_SOURCE_FILE}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"
RECIPIENTS_LIST="${RECIPIENTS_LIST:-$DEFAULT_RECIPIENTS_LIST}"
ITER_FILE="${ITER_FILE:-$DEFAULT_ITER_FILE}"
```
7. Функции логирования и обработки ошибок:
```
log() {
    printf -- "$(date '+%Y-%m-%d %T.%3N') $1\n" | tee -a "$LOG_FILE"
}

error_report() {
    local ERR_CODE=$?
    local ERR_LINE=${BASH_LINENO}
    local ERR_CMD=${BASH_COMMAND}
    log "Ошибка выполнения в строке ${ERR_LINE}: ${ERR_CMD} (${ERR_CODE})!"
    RESULT=${ERR_CODE}
    EXIT_CODE=${ERR_CODE}
}
trap 'error_report' ERR
```
#### Логика работы с файлами:
1. Функция проверки существования файла `.previous_iteration`, полный путь в переменной `ITER_FILE`. Если файл существует, то загружаем его содержимое (позиция в файле-источнике в виде "номер строки") в переменную `START_POSITION`, если значение пустое, то даем ему значение 1:
```
check_start_position() {
    trap 'error_report' ERR
    log "INFO: Получение позиции, на которой закончилась прошлая итерация"
    if [ -f "$ITER_FILE" ] && [ -s "$ITER_FILE" ]; then
        START_POSITION=$(<"$ITER_FILE")
    fi
    START_POSITION=${START_POSITION:-1}
}
```
2. Функция получения количества строк в файле-источнике `SOURCE_FILE` в переменную `END_POSITION`. Если значение `END_POSITION` больше 0 и больше чем `START_POSITION` то функция завершается с кодом 0, иначе если `END_POSITION` равна `START_POSITION` значит новых строк нет, пишем значение `END_POSITION` в файл `ITER_FILE`, завершаем скрипт, если `END_POSITION` меньше `START_POSITION`, видимо произошла ротация логов - файл изменился, выводим ошибку и завершаем скрипт:
```
check_end_position() {
    trap 'error_report' ERR
    log "INFO: Получение количества строк в файле, для сравнения с предыдущей итерацией"
    if [ ! -f "$SOURCE_FILE" ]; then
        log "ERROR: Файл-источник $SOURCE_FILE не найден!"
        exit 1
    fi
    
    END_POSITION=$(wc -l < "$SOURCE_FILE")
    
    if [ "$END_POSITION" -gt 0 ] && [ "$END_POSITION" -gt "$START_POSITION" ]; then
        log "INFO: Найдены новые строки. Start: $START_POSITION, End: $END_POSITION"
        return 0
    elif [ "$END_POSITION" -eq "$START_POSITION" ]; then
        log "INFO: Новых строк нет. Start: $START_POSITION, End: $END_POSITION"
        echo "$END_POSITION" > "$ITER_FILE"
        log "INFO: В фале $ITER_FILE обновлена позиция $END_POSITION"
        exit 0
    elif [ "$END_POSITION" -lt "$START_POSITION" ]; then
        log "ERROR: Стартовая позиция ($START_POSITION) больше чем количество строк в файле ($END_POSITION). Возможно произошла ротация файла"
        exit 1
    else
        log "ERROR: Файл-источник пуст или другая непредвиденная ошибка. Start: $START_POSITION, End: $END_POSITION"
        exit 1
    fi
}
```
3. Функция записи номера последней отработанной строки (`END_POSITION`) в файл `.previous_iteration` (`ITER_FILE`):
```
write_end_position(){
    trap 'error_report' ERR
    log "INFO: Запись последней обработанной строки в файл"
    echo $END_POSITION > $ITER_FILE
    return 0
}
```
4. Функция выгрузки данных в файл-отчет (`ws_reports/начальная_метка-конечная_метка`):
```
create_report(){
    trap 'error_report' ERR
    log "INFO: Формирование отчета"
    START_DATE=$(sed -n "${START_POSITION}p" "$SOURCE_FILE" | grep -oP '\[\K[^\]]+' | head -1)
    END_DATE=$(sed -n "${END_POSITION}p" "$SOURCE_FILE" | grep -oP '\[\K[^\]]+' | head -1)
    [ -d "./ws_reports" ] || mkdir -p ./ws_reports
    echo "ОТЧЕТ ЗА ПЕРИОД: $START_DATE - $END_DATE" > "./ws_reports/$START_POSITION-$END_POSITION"
    echo "Список ip-адресов:" >> "./ws_reports/$START_POSITION-$END_POSITION"
    for i in "${!IP_COUNTER[@]}"; do echo "$i: ${IP_COUNTER[$i]}"; done | sort -rn -k2 >> "./ws_reports/$START_POSITION-$END_POSITION"
    echo "Список URL:" >> "./ws_reports/$START_POSITION-$END_POSITION"
    for i in "${!URL_COUNTER[@]}"; do echo "$i: ${URL_COUNTER[$i]}"; done | sort -rn -k2 -t':' >> "./ws_reports/$START_POSITION-$END_POSITION"
    echo "Список HTTP кодов:" >> "./ws_reports/$START_POSITION-$END_POSITION"
    for i in "${!CODES_COUNTER[@]}"; do echo "$i: ${CODES_COUNTER[$i]}"; done | sort -rn -k2 -t':' >> "./ws_reports/$START_POSITION-$END_POSITION"
}
```
5. Функция формирования и отправки письма:
```
send_email(){
    trap 'error_report' ERR
    log "INFO: Отправка письма $1"
    mail -s "Отчет" $1 < "./ws_reports/$START_POSITION-$END_POSITION"
}
```

#### Логика поиска текстовых вхождений:
1. Функция поиска ip-адреса в переданной ей текстовой переменной и помещение его в ассоциативный массив:
```
declare -A IP_COUNTER
extract_and_count_ip() {
    local line="$1"
    local ip=""
    ip=$(echo "$line" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+') 
    if [[ -n "${IP_COUNTER[$ip]}" ]]; then
            ((IP_COUNTER[$ip]++))
        else
            IP_COUNTER[$ip]=1
    fi
}
```
вывод такого массива по убыванию количества:
```
for i in "${!IP_COUNTER[@]}"; do echo "$i: ${IP_COUNTER[$i]}"; done | sort -rn -k2
```
2. Функция поиска URL в переданной ей текстовой переменной и помещение его в ассоциативный массив:
```
declare -A URL_COUNTER
extract_and_count_url() {
    local line="$1"
    local url=""  
    url=$(echo "$line" | awk '{print $7}')
    if [ -n "$url" ]; then
        if [[ -n "${URL_COUNTER[$url]}" ]]; then
            ((URL_COUNTER[$url]++))
        else
            URL_COUNTER[$url]=1
        fi
    fi
}
```
вывод такого массива по убыванию количества:
```
for i in "${!URL_COUNTER[@]}"; do echo "$i: ${URL_COUNTER[$i]}"; done | sort -rn -k2 -t':'
```
3. Функция поиска HTTP-кодов ответов в переданной ей текстовой переменной и помещение его в ассоциативный массив:
```
declare -A CODES_COUNTER
extract_and_count_http_codes() {
    local line="$1"
    local code=""  
    code=$(echo "$line" | awk '{print $9}')
    if [ -n "$code" ]; then
        if [[ -n "${CODES_COUNTER[$code]}" ]]; then
            ((CODES_COUNTER[$code]++))
        else
            CODES_COUNTER[$code]=1
        fi
    fi
}
```
вывод такого массива по убыванию количества:
```
for i in "${!CODES_COUNTER[@]}"; do echo "$i: ${CODES_COUNTER[$i]}"; done | sort -rn -k2 -t':'
```
4. Цикл по строкам, в теле которого будут вызываться функции поиска:
```
for ((line_num=$START_POSITION; line_num<=$END_POSITION; line_num++)); do
    LINE_TEXT=$(sed -n "${line_num}p" "$SOURCE_FILE")
    extract_and_count_ip $LINE_TEXT
    extract_and_count_url "$LINE_TEXT"
    extract_and_count_http_codes "$LINE_TEXT"
done
```
#### Основное тело скрипта
```
check_start_position
check_end_position
for ((line_num=$START_POSITION; line_num<=$END_POSITION; line_num++)); do
    LINE_TEXT=$(sed -n "${line_num}p" "$SOURCE_FILE")
    extract_and_count_ip "$LINE_TEXT"
    extract_and_count_url "$LINE_TEXT"
    extract_and_count_http_codes "$LINE_TEXT"
done
write_end_position
create_report
send_email $RECIPIENTS_LIST
```
