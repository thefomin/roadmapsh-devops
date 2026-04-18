#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Конфигурация
ARCHIVE_DIR="/var/log/archives"
LOG_FILE="/var/log/log-archive.log"
DAYS_TO_KEEP=30


# Загрузка переменных из .env файла
load_env_file() {
    local script_dir=$(dirname "$(realpath "$0")")
    local env_file="${script_dir}/.env"
    
    if [ -f "$env_file" ]; then
        echo "Загружаю конфигурацию из $env_file" >&2
        # Читаем файл .env, игнорируя комментарии и пустые строки
        while IFS='=' read -r key value; do
            # Пропускаем комментарии и пустые строки
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z "$key" ]] && continue
            
            # Убираем пробелы
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            
            # Убираем кавычки, если они есть
            value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            
            # Экспортируем переменную
            export "$key=$value"
        done < "$env_file"
        return 0
    else
        echo "Файл .env не найден: $env_file" >&2
        return 1
    fi
}

# Загружаем .env файл
load_env_file

# Telegram конфигурация из переменных окружения
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

echo "DEBUG: TELEGRAM_BOT_TOKEN = ${TELEGRAM_BOT_TOKEN:0:10}..." >&2
echo "DEBUG: TELEGRAM_CHAT_ID = ${TELEGRAM_CHAT_ID}" >&2

# Функция логирования
log_message() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE" >&2
}

# Функция отображения использования
show_usage() {
    echo -e "${GREEN}Использование:${NC}"
    echo "  $0 <log-directory> [options]"
    echo ""
    echo -e "${GREEN}Опции:${NC}"
    echo "  -h, --help              Показать эту справку"
    echo "  -e, --email EMAIL       Отправить уведомление на email"
    echo "  -t, --telegram          Отправить уведомление в Telegram"
    echo "  -r, --remote URL        Отправить архив на удаленный сервер (rsync)"
    echo "  -k, --keep DAYS         Дней хранить архивы (по умолчанию: $DAYS_TO_KEEP)"
    echo ""
    echo -e "${GREEN}Переменные окружения:${NC}"
    echo "  TELEGRAM_BOT_TOKEN      Токен Telegram бота"
    echo "  TELEGRAM_CHAT_ID        ID чата Telegram"
    echo ""
    echo -e "${GREEN}Примеры:${NC}"
    echo "  $0 /var/log"
    echo "  $0 /var/log --telegram"
    echo "  $0 /var/log --email admin@example.com"
}

# Функция создания архива
create_archive() {
    local log_dir=$1
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    local archive_name="logs_archive_${timestamp}.tar.gz"
    local archive_path="${ARCHIVE_DIR}/${archive_name}"
    
    log_message "INFO" "Начинаю архивирование логов из ${log_dir}"
    
    if [ ! -d "$log_dir" ]; then
        log_message "ERROR" "Директория не существует: $log_dir"
        return 1
    fi
    
    local dir_name=$(basename "$log_dir")
    local parent_dir=$(dirname "$log_dir")
    local exclude_file="/tmp/tar_exclude_$$.txt"
    
    # Исключаем директорию архивов
    echo "$(basename "$ARCHIVE_DIR")" > "$exclude_file"
    
    log_message "INFO" "Создаю архив: $archive_path"
    
    # Создаем архив с игнорированием ошибок
    tar --warning=no-file-changed --ignore-failed-read \
        --exclude-from="$exclude_file" \
        -czf "$archive_path" -C "$parent_dir" "$dir_name" 2>&1 | \
        grep -v "file changed as we read it" | \
        grep -v "socket ignored" | \
        tee -a "$LOG_FILE"
    
    local tar_exit_code=${PIPESTATUS[0]}
    rm -f "$exclude_file"
    
    if [ $tar_exit_code -eq 0 ] && [ -f "$archive_path" ] && [ -s "$archive_path" ]; then
        local archive_size=$(du -h "$archive_path" 2>/dev/null | cut -f1)
        log_message "SUCCESS" "Архив создан: ${archive_path} (${archive_size})"
        printf "%s" "$archive_path"
        return 0
    else
        log_message "ERROR" "Ошибка при создании архива (код: $tar_exit_code)"
        rm -f "$archive_path" 2>/dev/null
        return 1
    fi
}

# Функция отправки email
send_email_notification() {
    local email=$1
    local archive_path=$2
    local log_dir=$3
    
    if [ ! -f "$archive_path" ]; then
        log_message "ERROR" "Файл архива не найден: $archive_path"
        return 1
    fi
    
    local archive_size=$(du -h "$archive_path" 2>/dev/null | cut -f1)
    
    if command -v mail &> /dev/null; then
        local subject="Log Archive: $(basename "$archive_path")"
        local body="Здравствуйте,

Архив логов успешно создан.

Детали:
- Директория логов: ${log_dir}
- Архив: ${archive_path}
- Размер: ${archive_size}
- Дата: $(date '+%Y-%m-%d %H:%M:%S')

С уважением,
Log Archive System"

        echo "$body" | mail -s "$subject" "$email"
        log_message "INFO" "Email уведомление отправлено на ${email}"
    else
        log_message "WARNING" "Команда 'mail' не найдена"
    fi
}

# Функция отправки в Telegram
send_telegram_notification() {
    local archive_path=$1
    local log_dir=$2
    
    if [ ! -f "$archive_path" ]; then
        log_message "ERROR" "Файл архива не найден: $archive_path"
        return 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_message "WARNING" "curl не установлен"
        return 1
    fi
    
    # Проверяем наличие переменных
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        log_message "ERROR" "Telegram не настроен. Проверьте .env файл"
        log_message "ERROR" "TELEGRAM_BOT_TOKEN: ${TELEGRAM_BOT_TOKEN:-не задан}"
        log_message "ERROR" "TELEGRAM_CHAT_ID: ${TELEGRAM_CHAT_ID:-не задан}"
        return 1
    fi
    
    local archive_size=$(du -h "$archive_path" 2>/dev/null | cut -f1)
    
    local message="УВЕДОМЛЕНИЕ ОБ АРХИВАЦИИ ЛОГОВ

Статус: УСПЕШНО
Директория логов: ${log_dir}
Архив: $(basename "$archive_path")
Размер: ${archive_size}
Время создания: $(date '+%Y-%m-%d %H:%M:%S')
Сервер: $(hostname)"

    # Отправляем запрос к Telegram API
    local response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${message}" 2>&1)
    
    # Проверяем ответ
    if echo "$response" | grep -q '"ok":true'; then
        log_message "SUCCESS" "Telegram уведомление отправлено успешно"
        return 0
    else
        log_message "ERROR" "Ошибка при отправке Telegram уведомления"
        log_message "ERROR" "Ответ API: $response"
        return 1
    fi
}

# Функция отправки на удаленный сервер
send_to_remote() {
    local remote_url=$1
    local archive_path=$2
    
    if [ ! -f "$archive_path" ]; then
        log_message "ERROR" "Файл архива не найден: $archive_path"
        return 1
    fi
    
    if command -v rsync &> /dev/null; then
        log_message "INFO" "Отправка архива на ${remote_url}"
        if rsync -avz "$archive_path" "$remote_url" 2>&1 | tee -a "$LOG_FILE"; then
            log_message "SUCCESS" "Архив успешно отправлен"
        else
            log_message "ERROR" "Ошибка при отправке архива"
        fi
    else
        log_message "WARNING" "rsync не установлен"
    fi
}

# Функция очистки старых архивов
cleanup_old_archives() {
    local days=$1
    log_message "INFO" "Удаляю архивы старше ${days} дней"
    
    if [ -d "$ARCHIVE_DIR" ]; then
        local old_count=$(find "$ARCHIVE_DIR" -name "logs_archive_*.tar.gz" -type f -mtime +${days} 2>/dev/null | wc -l)
        find "$ARCHIVE_DIR" -name "logs_archive_*.tar.gz" -type f -mtime +${days} -delete 2>/dev/null
        if [ $old_count -gt 0 ]; then
            log_message "INFO" "Удалено $old_count старых архивов"
        fi
    fi
}

# Функция отображения статистики
show_statistics() {
    local log_dir=$1
    
    echo -e "\n${BLUE}=========================================${NC}"
    echo -e "${GREEN}СТАТИСТИКА АРХИВАЦИИ ЛОГОВ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    
    if [ -d "$log_dir" ]; then
        local logs_size=$(du -sh "$log_dir" 2>/dev/null | cut -f1)
        local logs_count=$(find "$log_dir" -type f 2>/dev/null | wc -l)
        
        echo -e "Директория логов: ${YELLOW}$log_dir${NC}"
        echo -e "Размер логов:      ${GREEN}${logs_size:-0}${NC}"
        echo -e "Количество файлов: ${GREEN}${logs_count:-0}${NC}"
    fi
    
    if [ -d "$ARCHIVE_DIR" ]; then
        local archives_count=$(find "$ARCHIVE_DIR" -name "logs_archive_*.tar.gz" 2>/dev/null | wc -l)
        local archives_total_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)
        
        echo -e "\nАрхивов создано:   ${GREEN}${archives_count:-0}${NC}"
        echo -e "Общий размер:      ${GREEN}${archives_total_size:-0}${NC}"
        echo -e "Директория архивов: ${YELLOW}$ARCHIVE_DIR${NC}"
    fi
    
    echo -e "${BLUE}=========================================${NC}\n"
}

# Функция проверки директории архивов
ensure_archive_dir() {
    if [ ! -d "$ARCHIVE_DIR" ]; then
        mkdir -p "$ARCHIVE_DIR" 2>/dev/null
        if [ ! -d "$ARCHIVE_DIR" ]; then
            log_message "ERROR" "Не удалось создать директорию архивов"
            return 1
        fi
        chmod 755 "$ARCHIVE_DIR" 2>/dev/null
        log_message "INFO" "Создана директория архивов: $ARCHIVE_DIR"
    fi
    
    if [ ! -w "$ARCHIVE_DIR" ]; then
        log_message "ERROR" "Нет прав на запись в $ARCHIVE_DIR"
        return 1
    fi
    
    return 0
}

# Главная функция
main() {
    # Проверка аргументов
    if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    local log_dir="$1"
    local email=""
    local telegram=false
    local remote_url=""
    local keep_days=$DAYS_TO_KEEP
    
    # Парсим опции
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            -e|--email)
                email="$2"
                shift 2
                ;;
            -t|--telegram)
                telegram=true
                shift
                ;;
            -r|--remote)
                remote_url="$2"
                shift 2
                ;;
            -k|--keep)
                keep_days="$2"
                shift 2
                ;;
            *)
                log_message "ERROR" "Неизвестная опция: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Проверяем существование директории логов
    if [ ! -d "$log_dir" ]; then
        log_message "ERROR" "Директория не существует: $log_dir"
        exit 1
    fi
    
    # Создаем директорию для архивов
    if ! ensure_archive_dir; then
        exit 1
    fi
    
    # Показываем статистику
    show_statistics "$log_dir"
    
    # Создаем архив
    archive_path=$(create_archive "$log_dir")
    local create_status=$?
    
    # Проверяем успешность создания архива
    if [ $create_status -ne 0 ] || [ -z "$archive_path" ] || [ ! -f "$archive_path" ]; then
        log_message "ERROR" "Не удалось создать архив"
        exit 1
    fi
    
    # Отправляем email если указан
    if [ -n "$email" ]; then
        send_email_notification "$email" "$archive_path" "$log_dir"
    fi
    
    # Отправляем в Telegram если указано
    if [ "$telegram" = true ]; then
        send_telegram_notification "$archive_path" "$log_dir"
    fi
    
    # Отправляем на удаленный сервер если указан
    if [ -n "$remote_url" ]; then
        send_to_remote "$remote_url" "$archive_path"
    fi
    
    # Очищаем старые архивы
    cleanup_old_archives "$keep_days"
    
    log_message "SUCCESS" "Процесс архивации завершен успешно"
    
    echo -e "\n${GREEN}ГОТОВО! Архив сохранен: ${archive_path}${NC}"
}

# Запуск главной функции
main "$@"
