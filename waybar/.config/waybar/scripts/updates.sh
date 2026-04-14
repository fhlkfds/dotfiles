#!/usr/bin/env bash

set -euo pipefail

TERMINAL="kitty"
PACMAN_ICON="󰮯"
AUR_ICON="󰣇"
OK_ICON=""
WARN_ICON="󰀦"

get_repo_updates() {
    if command -v checkupdates >/dev/null 2>&1; then
        checkupdates 2>/dev/null | wc -l
    else
        echo 0
    fi
}

get_aur_updates() {
    if command -v paru >/dev/null 2>&1; then
        paru -Qua 2>/dev/null | wc -l
    elif command -v yay >/dev/null 2>&1; then
        yay -Qua 2>/dev/null | wc -l
    else
        echo 0
    fi
}

run_updates() {
    if ! command -v "$TERMINAL" >/dev/null 2>&1; then
        notify-send "Waybar Updates" "Terminal '$TERMINAL' not found."
        exit 1
    fi

    "$TERMINAL" -e bash -lc '
        set -e
        echo "== Arch Linux Update =="
        echo

        if pgrep -x pacman >/dev/null 2>&1; then
            echo "pacman is already running."
            echo
            read -n 1 -s -r -p "Press any key to close..."
            exit 1
        fi

        sudo pacman -Syu

        if command -v paru >/dev/null 2>&1; then
            echo
            read -r -p "Update AUR packages with paru too? [y/N]: " aur_reply
            if [[ "$aur_reply" =~ ^[Yy]$ ]]; then
                paru -Sua
            fi
        elif command -v yay >/dev/null 2>&1; then
            echo
            read -r -p "Update AUR packages with yay too? [y/N]: " aur_reply
            if [[ "$aur_reply" =~ ^[Yy]$ ]]; then
                yay -Sua
            fi
        fi

        echo
        echo "Update finished."
        read -n 1 -s -r -p "Press any key to close..."
    '
}

print_status() {
    local repo_updates aur_updates total text tooltip class

    repo_updates="$(get_repo_updates)"
    aur_updates="$(get_aur_updates)"
    total=$((repo_updates + aur_updates))

    if [[ "$total" -eq 0 ]]; then
        text="$OK_ICON 0"
        tooltip="System is up to date"
        class="ok"
    else
        text="$WARN_ICON $total"
        tooltip="Repo: $repo_updates"$'\n'"AUR: $aur_updates"$'\n'"Click to update"
        class="updates"
    fi

    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
}

case "${1:-}" in
    update)
        run_updates
        ;;
    *)
        print_status
        ;;
esac
