#!/usr/bin/env bash
set -euo pipefail

HYPR_DIR="${HOME}/.config/hypr"
TARGET_FILE="${1:-${HYPR_DIR}/conf/keybinding.conf}"

if [[ ! -f "$TARGET_FILE" ]]; then
    printf 'Error: file not found: %s\n' "$TARGET_FILE" >&2
    exit 1
fi

if ! command -v rofi >/dev/null 2>&1; then
    printf 'Error: rofi is not installed.\n' >&2
    exit 1
fi

declare -A VARS

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

load_vars() {
    local file line key value
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%%#*}"
            line="$(trim "$line")"
            [[ -z "$line" ]] && continue

            if [[ "$line" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
                key="${BASH_REMATCH[1]}"
                value="$(trim "${BASH_REMATCH[2]}")"
                VARS["$key"]="$value"
            fi
        done < "$file"
    done < <(find "$HYPR_DIR" -type f -name '*.conf' 2>/dev/null | sort)
}

expand_vars() {
    local s="$1"
    local old=""
    local name

    for _ in {1..10}; do
        old="$s"
        for name in "${!VARS[@]}"; do
            s="${s//\$$name/${VARS[$name]}}"
        done
        [[ "$s" == "$old" ]] && break
    done

    printf '%s' "$s"
}

pretty_mods() {
    local mods="$1"
    local out=()
    local part

    mods="$(trim "$mods")"
    mods="$(expand_vars "$mods")"
    mods="$(tr -s ' ' <<< "$mods")"

    [[ -z "$mods" ]] && {
        printf 'None'
        return
    }

    read -r -a parts <<< "$mods"

    for part in "${parts[@]}"; do
        case "${part^^}" in
            SUPER|WIN|META) out+=("Super") ;;
            SHIFT) out+=("Shift") ;;
            CTRL|CONTROL) out+=("Ctrl") ;;
            ALT|MOD1) out+=("Alt") ;;
            MOD2) out+=("Mod2") ;;
            MOD3) out+=("Mod3") ;;
            MOD4) out+=("Mod4") ;;
            MOD5) out+=("Mod5") ;;
            *) out+=("$part") ;;
        esac
    done

    local joined=""
    local i
    for i in "${!out[@]}"; do
        [[ $i -gt 0 ]] && joined+=" + "
        joined+="${out[$i]}"
    done

    printf '%s' "$joined"
}

pretty_key() {
    local key="$1"
    key="$(trim "$key")"
    key="$(expand_vars "$key")"

    case "${key^^}" in
        RETURN|ENTER) printf 'Enter' ;;
        SPACE) printf 'Space' ;;
        TAB) printf 'Tab' ;;
        ESC|ESCAPE) printf 'Esc' ;;
        BACKSPACE) printf 'Backspace' ;;
        DELETE) printf 'Delete' ;;
        HOME) printf 'Home' ;;
        END) printf 'End' ;;
        PAGEUP) printf 'PageUp' ;;
        PAGEDOWN) printf 'PageDown' ;;
        LEFT) printf 'Left' ;;
        RIGHT) printf 'Right' ;;
        UP) printf 'Up' ;;
        DOWN) printf 'Down' ;;
        PRINT) printf 'Print' ;;
        CAPSLOCK) printf 'CapsLock' ;;
        *) printf '%s' "$key" ;;
    esac
}

build_menu() {
    local line bind_type rhs mods key dispatcher args
    local -a parts
    local pretty_combo action
    local found=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="$(trim "$line")"
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^(bind[a-z]*)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            bind_type="${BASH_REMATCH[1]}"
            rhs="${BASH_REMATCH[2]}"

            IFS=',' read -r -a parts <<< "$rhs"
            [[ ${#parts[@]} -lt 3 ]] && continue

            mods="$(trim "${parts[0]}")"
            key="$(trim "${parts[1]}")"
            dispatcher="$(trim "${parts[2]}")"

            args=""
            if [[ ${#parts[@]} -gt 3 ]]; then
                args="$(trim "${parts[3]}")"
                if [[ ${#parts[@]} -gt 4 ]]; then
                    local i
                    for (( i=4; i<${#parts[@]}; i++ )); do
                        args+=", $(trim "${parts[i]}")"
                    done
                fi
            fi

            dispatcher="$(expand_vars "$dispatcher")"
            args="$(expand_vars "$args")"

            pretty_combo="$(pretty_mods "$mods")"
            if [[ "$(pretty_key "$key")" != "None" ]]; then
                if [[ "$pretty_combo" == "None" ]]; then
                    pretty_combo="$(pretty_key "$key")"
                else
                    pretty_combo+=" + $(pretty_key "$key")"
                fi
            fi

            if [[ -n "$args" ]]; then
                action="${dispatcher}: ${args}"
            else
                action="${dispatcher}"
            fi

            printf '%-30s | %-8s | %s\n' "$pretty_combo" "$bind_type" "$action"
            found=1
        fi
    done < "$TARGET_FILE"

    [[ $found -eq 1 ]]
}

load_vars

MENU_CONTENT="$(build_menu || true)"

if [[ -z "${MENU_CONTENT:-}" ]]; then
    notify-send "Hyprland keybinds" "No keybinds found in $TARGET_FILE" 2>/dev/null || true
    exit 1
fi

selection="$(
    printf '%s\n' "$MENU_CONTENT" |
    rofi -dmenu \
        -i \
        -p "Hyprland keybinds" \
        -config "$HOME/.config/rofi/comet-glass.rasi"
)"
[[ -z "${selection:-}" ]] && exit 0

if command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$selection" | wl-copy
    notify-send "Hyprland keybinds" "Copied selected keybind to clipboard" 2>/dev/null || true
else
    notify-send "Hyprland keybinds" "$selection" 2>/dev/null || true
fi
