#!/bin/bash

FILE="wghub.conf"
BACKUP="wghub.conf.bak"

if [[ ! -f "$FILE" ]]; then
    echo "[ERROR] Файл $FILE не найден."
    exit 1
fi

cp "$FILE" "$BACKUP"
echo "[OK] Резервная копия создана: $BACKUP"

declare -a BLOCKS_START
declare -a BLOCKS_END
declare -a BLOCKS_TEXT
declare -a BLOCKS_LABEL
declare -a BLOCKS_NOTE
declare -a BLOCKS_COMMENTED

parse_blocks() {
    BLOCKS_START=()
    BLOCKS_END=()
    BLOCKS_TEXT=()
    BLOCKS_LABEL=()
    BLOCKS_NOTE=()
    BLOCKS_COMMENTED=()

    local total=$(wc -l < "$FILE")
    local inside=0
    local start=0
    local content=""

    for ((i = 1; i <= total; i++)); do
        line=$(sed -n "${i}p" "$FILE")

        if [[ "$line" =~ \[Peer\] ]]; then
            inside=1
            start=$i
            content=""
            continue
        fi

        if [[ $inside -eq 1 ]]; then
            content+="$line"$'\n'
            if [[ "$line" =~ AllowedIPs[[:space:]]*= ]]; then
                inside=0
                BLOCKS_START+=("$start")
                BLOCKS_END+=("$i")

                formatted=$(echo "$content" | grep -v '\[Peer\]' | \
                    sed -E 's/(PublicKey[[:space:]]*=[[:space:]]*)(.{16}).*/\1\2.../g' | \
                    sed -E 's/(PresharedKey[[:space:]]*=[[:space:]]*)(.{16}).*/\1\2.../g')
                BLOCKS_TEXT+=("$formatted")

                local label=$(echo "$content" | grep -E "wgclient_" | head -n1 | sed -E 's/^[[:space:]]*#?[[:space:]]*//')

                local note=""
                for ((j=start-1; j>=1; j--)); do
                    line_above=$(sed -n "${j}p" "$FILE")
                    if [[ "$line_above" =~ ^#\ *Note: ]]; then
                        note=$(echo "$line_above" | sed -E 's/^# *Note:[[:space:]]*//')
                        break
                    elif [[ ! "$line_above" =~ ^# ]]; then
                        break
                    fi
                done

                if [[ -n "$note" ]]; then
                    label="$label ($note)"
                fi

                [[ -z "$label" ]] && label="(без подписи)"

                # Проверка на закомментированность блока
                local is_commented=$(sed -n "${start}p" "$FILE" | grep -c '^#')
                BLOCKS_COMMENTED+=("$is_commented")

                BLOCKS_LABEL+=("$label")
                content=""
            fi
        fi
    done
}

restart_wireguard() {
    echo -n "[RESTART] Перезапустить WireGuard с новым конфигом? (y/N): "
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo "[INFO] Отключение WireGuard..."
        if wg-quick down ./wghub.conf; then
            echo "[OK] Отключено."
        else
            echo "[WARN] Ошибка при отключении. Продолжаем..."
        fi
        echo "[INFO] Запуск WireGuard..."
        if wg-quick up ./wghub.conf; then
            echo "[OK] WireGuard перезапущен."
        else
            echo "[ERROR] Не удалось запустить WireGuard."
        fi
    else
        echo "[CANCELLED] Отменено."
    fi
}

print_blocks() {
    clear

    local h1="№"
    local h2="Подпись"
    local h3="PublicKey"
    local h4="PresharedKey"
    local h5="AllowedIPs"

    printf "\n%-6s | %-39s | %-32s | %-32s | %-20s\n" "$h1" "$h2" "$h3" "$h4" "$h5"
    printf "%s\n" "-------------------------------------------------------------------------------------------------------------------------------------"

    for i in "${!BLOCKS_TEXT[@]}"; do
        local index=$((i + 1))
        local label="${BLOCKS_LABEL[$i]}"

        if [[ "${BLOCKS_COMMENTED[$i]}" -eq 1 ]]; then
            label="*** $label ***"
        fi

        if (( ${#label} > 32 )); then
            label="$(echo "$label" | awk '{ print substr($0,1,29) "..." }')"
        else
            pad_len=$((32 - ${#label}))
            label="$label$(printf '%*s' "$pad_len")"
        fi

        local pub="" pre="" allow=""

        if [[ "${BLOCKS_COMMENTED[$i]}" -eq 1 ]]; then
            pub="*"; pre="*"; allow="*"
        else
            while IFS= read -r line; do
                case "$line" in
                    PublicKey\ =*)
                        pub=$(echo "$line" | awk -F= '{gsub(/^[ \t]+/, "", $2); print substr($2, 1, 16) "..."}')
                        ;;
                    PresharedKey\ =*)
                        pre=$(echo "$line" | awk -F= '{gsub(/^[ \t]+/, "", $2); print substr($2, 1, 16) "..."}')
                        ;;
                    AllowedIPs\ =*)
                        tmp=$(echo "$line" | cut -d= -f2- | sed -E 's/^[ \t]+//')
                        allow=$(echo "$tmp" | tr ',' '\n' | grep -v ":" | tr '\n' ',' | sed 's/,\$//')
                        ;;
                esac
            done <<< "${BLOCKS_TEXT[$i]}"
        fi

        printf "%-4s | %-32s | %-32s | %-32s | %-20s\n" "$index" "$label" "$pub" "$pre" "$allow"
    done
    echo
}

search_blocks() {
    clear
    echo -n "[SEARCH] Введите строку для поиска: "
    read -r term

    local found=0
    for i in "${!BLOCKS_TEXT[@]}"; do
        if echo "${BLOCKS_TEXT[$i]}" | grep -qi "$term" || echo "${BLOCKS_LABEL[$i]}" | grep -qi "$term"; then
            echo "------------------------"
            echo "$((i + 1))) ${BLOCKS_LABEL[$i]}"
            echo "${BLOCKS_TEXT[$i]}"
            found=1
        fi
        
    done
    
    [[ $found -eq 0 ]] && echo "[INFO] Ничего не найдено."
    
}

delete_block_by_index() {
    echo -n "Введите номер пользователя для удаления: "
    read -r idx
    ((idx--))
    if [[ -z "${BLOCKS_START[$idx]}" ]]; then
        echo "[ERROR] Неверный номер."
        return
    fi
    sed -i "${BLOCKS_START[$idx]},${BLOCKS_END[$idx]}d" "$FILE"
    echo "[OK] Пользователь $((idx+1)) удалён."
    restart_wireguard
}

comment_block_by_index() {
    echo -n "Введите номер пользователя для деактивации: "
    read -r idx
    ((idx--))
    if [[ -z "${BLOCKS_START[$idx]}" ]]; then
        clear
        echo "[ERROR] Неверный номер."
        return
    fi

    # Проверка на уже закомментированный блок
    if sed -n "${BLOCKS_START[$idx]}p" "$FILE" | grep -q '^#'; then
        clear
        echo "[INFO] Пользователь уже деактивирован. Пропуск."
        return
    fi

    sed -i "${BLOCKS_START[$idx]},${BLOCKS_END[$idx]}s/^/# /" "$FILE"
    clear
    echo "[OK] Пользователь $((idx+1)) деактивирован."
    restart_wireguard
}

uncomment_block_by_index() {
    echo -n "Введите номер пользователя для активации: "
    read -r idx
    ((idx--))
    if [[ -z "${BLOCKS_START[$idx]}" ]]; then
        echo "[ERROR] Неверный номер."
        return
    fi
    sed -i "${BLOCKS_START[$idx]},${BLOCKS_END[$idx]}s/^#[[:space:]]*//" "$FILE"
    clear
    echo "[OK] Пользователь $((idx+1)) активирован."
    restart_wireguard
}

while true; do
    parse_blocks
    echo
    echo "========= МЕНЮ ========="
    echo "1. Показать всех пользователей"
    echo "2. Найти пользователя по содержимому"
    echo "3. Удалить пользователя по номеру"
    echo "4. Деактивация пользователя"
    echo "5. Активация пользователя"
    echo "6. Перезапустить WireGuard"
    echo "7. Выйти"
    echo "========================"
    echo -n "Выберите: "
    read -r action

    case "$action" in
        1) print_blocks ;;
        2) search_blocks ;;
        3) delete_block_by_index ;;
        4) comment_block_by_index ;;
        5) uncomment_block_by_index ;;
        6) restart_wireguard ;;
        7) echo "[INFO] Выход."; clear; exit 0 ;;
        *) echo "[WARN] Неверный ввод." ;;
    esac
done




