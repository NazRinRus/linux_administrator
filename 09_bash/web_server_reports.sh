#!/bin/bash

LOCK_FILE="/var/run/$(basename "$0").lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Уже запущен экземпляр данного скрипта"
    exit 1
fi
echo "Запущен скрипт - PID $$"

DEFAULT_SOURCE_FILE="/opt/scripts/web_server_reports/access_test.log"
DEFAULT_LOG_FILE="/opt/scripts/web_server_reports/ws_report.log"
DEFAULT_ITER_FILE="/opt/scripts/web_server_reports/.previous_iteration"
DEFAULT_RECIPIENTS_LIST="nazrinrus@gmail.com"

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

SOURCE_FILE="${SOURCE_FILE:-$DEFAULT_SOURCE_FILE}"
LOG_FILE="${LOG_FILE:-$DEFAULT_LOG_FILE}"
RECIPIENTS_LIST="${RECIPIENTS_LIST:-$DEFAULT_RECIPIENTS_LIST}"
ITER_FILE="${ITER_FILE:-$DEFAULT_ITER_FILE}"

log() {
    printf -- "$(date '+%Y-%m-%d %T.%3N') $1\n" | tee -a "$LOG_FILE"
}

error_report() {
    local ERR_CODE=$?
    local ERR_LINE=${BASH_LINENO}
    local ERR_CMD=${BASH_COMMAND}
    log "Error occured on line ${ERR_LINE}: ${ERR_CMD} (${ERR_CODE})!"
    RESULT=${ERR_CODE}
    EXIT_CODE=${ERR_CODE}
}
trap 'error_report' ERR


check_start_position() {
    trap 'error_report' ERR
    log "Получение позиции, на которой закончилась прошлая итерация"
    if [ -f "$ITER_FILE" ] && [ -s "$ITER_FILE" ]; then
        START_POSITION=$(<"$ITER_FILE")
    fi
    START_POSITION=${START_POSITION:-1}
}

check_end_position() {
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

write_end_position(){
    trap 'error_report' ERR
    log "INFO: Запись последней обработанной строки в файл"
    echo $END_POSITION > $ITER_FILE
    return 0
}

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

send_email(){
    trap 'error_report' ERR
    log "INFO: Отправка письма $1"
    mail -s "Отчет" $1 < "./ws_reports/$START_POSITION-$END_POSITION"
}

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
