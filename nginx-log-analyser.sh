#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Функция для отображения использования
show_usage() {
    echo -e "${GREEN}Использование:${NC}"
    echo "  $0 <log-file> [options]"
    echo ""
    echo -e "${GREEN}Опции:${NC}"
    echo "  -h, --help              Показать эту справку"
    echo "  -n, --num N             Количество результатов (по умолчанию: 5)"
    echo "  -f, --format FORMAT     Формат вывода (table/csv/json) (по умолчанию: table)"
    echo "  -o, --output FILE       Сохранить результат в файл"
    echo ""
    echo -e "${GREEN}Примеры:${NC}"
    echo "  $0 access.log"
    echo "  $0 access.log -n 10"
    echo "  $0 access.log --format json --output result.json"
}

# Функция для анализа IP адресов
analyze_ips() {
    local log_file=$1
    local num=${2:-5}
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Топ-${num} IP-адресов с наибольшим количеством запросов:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    # Решение 1: Использование awk, sort, uniq
    awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count ip; do
        echo -e "  ${YELLOW}$ip${NC} - ${GREEN}$count${NC} запросов"
    done
}

# Функция для анализа маршрутов
analyze_paths() {
    local log_file=$1
    local num=${2:-5}
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Топ-${num} самых востребованных маршрутов:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    # Решение 2: Использование awk для извлечения пути (7-е поле)
    awk '{print $7}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count path; do
        echo -e "  ${YELLOW}$path${NC} - ${GREEN}$count${NC} запросов"
    done
}

# Функция для анализа кодов ответа
analyze_status_codes() {
    local log_file=$1
    local num=${2:-5}
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Топ-${num} самых распространенных кодов состояния ответа:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    # Решение 3: Использование awk для кодов ответа (9-е поле)
    awk '{print $9}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count code; do
        # Цветовая индикация кодов
        case $code in
            2*) color="${GREEN}";;
            3*) color="${YELLOW}";;
            4*) color="${RED}";;
            5*) color="${RED}";;
            *) color="${NC}";;
        esac
        echo -e "  ${color}$code${NC} - ${GREEN}$count${NC} запросов"
    done
}

# Функция для анализа User-Agent
analyze_user_agents() {
    local log_file=$1
    local num=${2:-5}
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}Топ-${num} пользовательских агентов:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    # Решение 4: Извлечение User-Agent (поля 12+)
    awk '{for(i=12;i<=NF;i++) printf "%s ", $i; printf "\n"}' "$log_file" | \
        sort | uniq -c | sort -rn | head -n "$num" | while read count agent; do
        # Обрезаем длинные агенты
        if [ ${#agent} -gt 60 ]; then
            agent="${agent:0:57}..."
        fi
        echo -e "  ${YELLOW}$agent${NC} - ${GREEN}$count${NC} запросов"
    done
}

# Альтернативная реализация с использованием grep и sed
analyze_with_grep_sed() {
    local log_file=$1
    local num=${2:-5}
    
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}АЛЬТЕРНАТИВНЫЙ АНАЛИЗ (с использованием grep и sed):${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════${NC}"
    
    echo -e "\n${YELLOW}Топ IP адресов:${NC}"
    grep -Eo '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$log_file" | sort | uniq -c | sort -rn | head -n "$num"
    
    echo -e "\n${YELLOW}Топ маршрутов:${NC}"
    grep -Eo '"(GET|POST|PUT|DELETE|PATCH) [^"]+' "$log_file" | \
        sed 's/"[A-Z]* //' | sort | uniq -c | sort -rn | head -n "$num"
    
    echo -e "\n${YELLOW}Топ кодов ответа:${NC}"
    grep -Eo ' [0-9]{3} ' "$log_file" | sort | uniq -c | sort -rn | head -n "$num"
}

# Функция для вывода в CSV формате
output_csv() {
    local log_file=$1
    local num=${2:-5}
    
    echo "Category,Value,Count"
    
    # IP addresses
    awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count ip; do
        echo "IP,${ip},${count}"
    done
    
    # Paths
    awk '{print $7}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count path; do
        echo "Path,${path},${count}"
    done
    
    # Status codes
    awk '{print $9}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count code; do
        echo "Status Code,${code},${count}"
    done
    
    # User Agents
    awk '{for(i=12;i<=NF;i++) printf "%s ", $i; printf "\n"}' "$log_file" | \
        sort | uniq -c | sort -rn | head -n "$num" | while read count agent; do
        echo "User Agent,\"${agent}\",${count}"
    done
}

# Функция для вывода в JSON формате
output_json() {
    local log_file=$1
    local num=${2:-5}
    
    echo "{"
    
    # IP addresses
    echo '  "top_ips": ['
    awk '{print $1}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count ip; do
        echo "    {\"ip\": \"${ip}\", \"requests\": ${count}}"
        echo -n ","
    done | sed '$ s/,$//'
    echo "  ],"
    
    # Paths
    echo '  "top_paths": ['
    awk '{print $7}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count path; do
        echo "    {\"path\": \"${path}\", \"requests\": ${count}}"
        echo -n ","
    done | sed '$ s/,$//'
    echo "  ],"
    
    # Status codes
    echo '  "top_status_codes": ['
    awk '{print $9}' "$log_file" | sort | uniq -c | sort -rn | head -n "$num" | while read count code; do
        echo "    {\"code\": \"${code}\", \"requests\": ${count}}"
        echo -n ","
    done | sed '$ s/,$//'
    echo "  ],"
    
    # User Agents
    echo '  "top_user_agents": ['
    awk '{for(i=12;i<=NF;i++) printf "%s ", $i; printf "\n"}' "$log_file" | \
        sort | uniq -c | sort -rn | head -n "$num" | while read count agent; do
        # Экранируем кавычки в JSON
        agent=$(echo "$agent" | sed 's/"/\\"/g')
        echo "    {\"user_agent\": \"${agent}\", \"requests\": ${count}}"
        echo -n ","
    done | sed '$ s/,$//'
    echo "  ]"
    
    echo "}"
}

# Функция для общей статистики
show_general_stats() {
    local log_file=$1
    
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}ОБЩАЯ СТАТИСТИКА:${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    
    local total_requests=$(wc -l < "$log_file")
    local unique_ips=$(awk '{print $1}' "$log_file" | sort -u | wc -l)
    local unique_paths=$(awk '{print $7}' "$log_file" | sort -u | wc -l)
    
    # Подсчет успешных и ошибочных запросов
    local success=$(awk '{print $9}' "$log_file" | grep -c '^2' 2>/dev/null || echo "0")
    local redirects=$(awk '{print $9}' "$log_file" | grep -c '^3' 2>/dev/null || echo "0")
    local client_errors=$(awk '{print $9}' "$log_file" | grep -c '^4' 2>/dev/null || echo "0")
    local server_errors=$(awk '{print $9}' "$log_file" | grep -c '^5' 2>/dev/null || echo "0")
    
    echo -e "  ${YELLOW}Всего запросов:${NC}      ${GREEN}$total_requests${NC}"
    echo -e "  ${YELLOW}Уникальных IP:${NC}        ${GREEN}$unique_ips${NC}"
    echo -e "  ${YELLOW}Уникальных маршрутов:${NC} ${GREEN}$unique_paths${NC}"
    echo -e "  ${YELLOW}Успешные (2xx):${NC}       ${GREEN}$success${NC}"
    echo -e "  ${YELLOW}Редиректы (3xx):${NC}      ${YELLOW}$redirects${NC}"
    echo -e "  ${YELLOW}Ошибки клиента (4xx):${NC} ${RED}$client_errors${NC}"
    echo -e "  ${YELLOW}Ошибки сервера (5xx):${NC} ${RED}$server_errors${NC}"
}

# Главная функция
main() {
    # Проверка аргументов
    if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        show_usage
        exit 0
    fi
    
    local log_file="$1"
    local num_results=5
    local format="table"
    local output_file=""
    
    # Парсим опции
    shift
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--num)
                num_results="$2"
                shift 2
                ;;
            -f|--format)
                format="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            *)
                echo -e "${RED}Ошибка: Неизвестная опция $1${NC}"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Проверяем существование файла
    if [ ! -f "$log_file" ]; then
        echo -e "${RED}Ошибка: Файл $log_file не найден${NC}"
        echo -e "${YELLOW}Скачайте пример лога:${NC}"
        echo "  curl -o access.log https://raw.githubusercontent.com/elastic/examples/master/Common%20Data%20Formats/nginx_logs/nginx_logs"
        exit 1
    fi
    
    # Создаем временный файл для вывода
    local temp_output=$(mktemp)
    
    # Перенаправляем вывод во временный файл
    exec > "$temp_output"
    
    # Выводим результаты в зависимости от формата
    case "$format" in
        csv)
            output_csv "$log_file" "$num_results"
            ;;
        json)
            output_json "$log_file" "$num_results"
            ;;
        table|*)
            echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}              АНАЛИЗ ЛОГ-ФАЙЛА: $(basename "$log_file")${NC}"
            echo -e "${PURPLE}════════════════════════════════════════════════════════════════${NC}"
            echo -e "  ${YELLOW}Дата анализа:${NC} $(date)"
            echo -e "  ${YELLOW}Размер файла:${NC} $(du -h "$log_file" | cut -f1)"
            
            show_general_stats "$log_file"
            analyze_ips "$log_file" "$num_results"
            analyze_paths "$log_file" "$num_results"
            analyze_status_codes "$log_file" "$num_results"
            analyze_user_agents "$log_file" "$num_results"
            
            # Показать альтернативный анализ
            analyze_with_grep_sed "$log_file" "$num_results"
            
            echo -e "\n${PURPLE}════════════════════════════════════════════════════════════════${NC}"
            ;;
    esac
    
    # Восстанавливаем стандартный вывод
    exec > /dev/tty
    
    # Сохраняем или выводим результат
    if [ -n "$output_file" ]; then
        cp "$temp_output" "$output_file"
        echo -e "${GREEN}Результат сохранен в $output_file${NC}"
    else
        cat "$temp_output"
    fi
    
    # Удаляем временный файл
    rm -f "$temp_output"
}

# Запуск главной функции
main "$@"
